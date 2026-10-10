//! Strict optimizer-equivalence gate: aliases or exact normalized instruction equality.
const std = @import("std");
const owner_names = [_][]const u8{ "secret_s32", "transfer_s32", "secret_s48", "transfer_s48", "secret_material", "transfer_material", "cleanup", "cleanup_material", "budget", "job", "increment" };
const numeric_names = [_][]const u8{ "numeric_add", "numeric_sub", "numeric_mul", "numeric_div", "numeric_rem", "numeric_shift", "numeric_saturating", "numeric_ranged", "numeric_cast", "numeric_identity", "numeric_counter", "numeric_count", "numeric_bits", "numeric_duration", "numeric_rounding", "numeric_instant", "numeric_invariant", "numeric_diagnostics", "numeric_encoding" };
const bytes_names = [_][]const u8{ "bytes_dead", "bytes_cleanup", "bytes_resize", "bytes_reserve", "bytes_move", "bytes_adopt_dead", "bytes_replace" };
const a67_names = [_][]const u8{ "a67_mutex", "a67_rw_read", "a67_rw_write", "a67_once_ready", "a67_once_cold", "a67_condition", "a67_array", "a67_queue", "a67_buffer", "a67_budget", "a67_owned", "a67_must_use", "a67_confined", "a67_ordered", "a67_ring_buffer", "a67_limit" };
const gaps_names = [_][]const u8{ "gaps_try_acquire", "gaps_teardown", "gaps_lazy_ready", "gaps_lazy_cold", "gaps_lazy_infallible", "gaps_shared_retain", "gaps_shared_get", "gaps_shared_release", "gaps_owned_from", "gaps_compare", "gaps_equal", "gaps_last", "gaps_exceeds", "gaps_io_widen", "gaps_io_timestamp", "gaps_io_narrow", "gaps_never", "gaps_index_compare", "gaps_owned_io", "gaps_wide_round_trip", "gaps_is_held", "gaps_saturating_add", "gaps_saturating_sub", "gaps_saturating_span", "gaps_id_successor", "gaps_id_advance", "gaps_id_retreat", "gaps_id_distance" };
const state_names = [_][]const u8{ "state_next", "state_next_wide", "state_next_switch", "state_next_wide_switch", "state_terminal", "state_step", "state_plan_commit", "state_transition", "state_transition_with", "state_take" };
const scope_names = [_][]const u8{ "scope_get", "scope_get_slice", "scope_make", "scope_reborrow", "scope_open", "scope_end", "scope_cycle" };
const names = owner_names ++ numeric_names ++ bytes_names ++ a67_names ++ gaps_names ++ state_names ++ scope_names;
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2) return error.ZigExecutableRequired;
    const record = args.len == 3 and std.mem.eql(u8, args[2], "--record");
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/parity");
    for ([_][]const u8{ "x86_64-linux-gnu", "aarch64-linux-gnu" }) |target| {
        for ([_][]const u8{ "ReleaseFast", "ReleaseSafe" }) |mode| {
            const stem = try a.print(".zig-cache/parity/{s}-{s}", .{ target, mode });
            const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", try a.print("-O{s}", .{mode}), "-target", target, "-mcpu=baseline", "-fllvm", "-fstrip", "--dep", "aegis", "--dep", "material", "-Mroot=ci/parity.zig", "-Maegis=src/root.zig", "-Mmaterial=src/testing/Material.zig", try a.print("-femit-llvm-ir={s}.ll", .{stem}), try a.print("-femit-asm={s}.s", .{stem}), try a.print("-femit-bin={s}.o", .{stem}), "--cache-dir", ".zig-cache/parity/cache", "--global-cache-dir", ".zig-cache/global" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(16384) });
            defer init.gpa.free(result.stdout);
            defer init.gpa.free(result.stderr);
            if (result.term != .exited or result.term.exited != 0) {
                var writer = std.Io.File.stderr().writer(init.io, &.{});
                try writer.interface.writeAll(result.stderr);
                return error.CodegenCompilationFailed;
            }
            const assembly = try dir.readFileAlloc(init.io, try a.print("{s}.s", .{stem}), a, .limited(32 * 1024 * 1024));
            const ir = try dir.readFileAlloc(init.io, try a.print("{s}.ll", .{stem}), a, .limited(32 * 1024 * 1024));
            const object = try dir.readFileAlloc(init.io, try a.print("{s}.o", .{stem}), a, .limited(32 * 1024 * 1024));
            var evidence: std.Io.Writer.Allocating = .init(a);
            try evidence.writer.print("# {s} {s} parity\n\nZig 0.17.0, LLVM, baseline CPU, stripped object. All owner, A3 scalar and A4 byte-owner pairs have identical emitted instructions (shared aliases or normalized assembly); storage/alignment assertions compile.\n\n", .{ target, mode });
            for (names) |name| {
                const base = try alias(a, ir, try exportName(a, "baseline", name));
                const wrap = try alias(a, ir, try exportName(a, "wrapper", name));
                const baseline_bytes = try symbolSize(object, try exportName(a, "baseline", name));
                const wrapper_bytes = try symbolSize(object, try exportName(a, "wrapper", name));
                // A `_switch` row compares against the idiomatic nested switch: the table may be smaller, never larger.
                const idiom = std.mem.endsWith(u8, name, "_switch");
                if (if (idiom) wrapper_bytes > baseline_bytes else baseline_bytes != wrapper_bytes) {
                    var failure = std.Io.File.stderr().writer(init.io, &.{});
                    try failure.interface.print("{s} {s} {s}: code size {d}/{d}\n", .{ target, mode, name, baseline_bytes, wrapper_bytes });
                    return error.AbstractionCodeSizeMismatch;
                }
                if (reported(name)) {
                    var numbers = std.Io.File.stdout().writerStreaming(init.io, &.{});
                    try numbers.interface.print("code,{s},{s},{s},{d},{d}\n", .{ name, target, mode, baseline_bytes, wrapper_bytes });
                }
                const emitted_base = try assemblyAlias(a, assembly, try exportName(a, "baseline", name));
                const emitted_wrap = try assemblyAlias(a, assembly, try exportName(a, "wrapper", name));
                const emitted = try instructions(a, assembly, emitted_base, target);
                if (!idiom and !std.mem.eql(u8, emitted_base, emitted_wrap)) {
                    const other = try instructions(a, assembly, emitted_wrap, target);
                    if (!std.mem.eql(u8, emitted, other)) {
                        var failure = std.Io.File.stderr().writer(init.io, &.{});
                        try failure.interface.print("{s} {s} {s}: instruction mismatch\n", .{ target, mode, name });
                        return error.AbstractionInstructionMismatch;
                    }
                }
                const body = try function(a, ir, base);
                const secret = std.mem.startsWith(u8, name, "bytes_") or std.mem.find(u8, name, "secret") != null or std.mem.startsWith(u8, name, "transfer") or std.mem.startsWith(u8, name, "cleanup");
                if (secret) {
                    if (std.mem.find(u8, body, "store volatile") == null and std.mem.find(u8, body, "i1 true)") == null) return error.MissingVolatileErasure;
                    if (std.mem.startsWith(u8, name, "bytes_")) {
                        // Descriptor-only erasure is insufficient: require a
                        // volatile allocation memset with a runtime extent.
                        var allocation_wipe = false;
                        var body_lines = std.mem.splitScalar(u8, body, '\n');
                        while (body_lines.next()) |line| {
                            if (std.mem.find(u8, line, "@llvm.memset.") != null and std.mem.find(u8, line, "i64 %") != null and std.mem.find(u8, line, "i1 true)") != null) allocation_wipe = true;
                        }
                        if (!allocation_wipe) return error.MissingFullCapacityErasure;
                        if (std.mem.eql(u8, name, "bytes_adopt_dead") and std.mem.find(u8, body, "i64 %2, i1 true)") == null) return error.MissingAdoptedCapacityErasure;
                    }
                } else if (owner(name)) {
                    const swapped = std.mem.find(u8, body, "atomicrmw xchg") != null and std.mem.find(u8, body, " acquire") != null;
                    const acquire = swapped or (std.mem.find(u8, body, "@llvm.aarch64.ldaxr") != null and std.mem.find(u8, body, "@llvm.aarch64.stxr") != null);
                    if (!acquire or std.mem.find(u8, body, "release") == null) return error.MissingLockOrdering;
                }
                try evidence.writer.print("## {s}\n\nSymbols → `{s}` / `{s}`; baseline/wrapper machine code {d}/{d} bytes.\n\n```asm\n{s}```\n\n```llvm\n{s}\n```\n\n", .{ name, base, wrap, baseline_bytes, wrapper_bytes, emitted, body });
            }
            if (record) try dir.writeFile(init.io, .{ .sub_path = try a.print(".zig-cache/parity/codegen-{s}-{s}.md", .{ target, mode }), .data = try a.print("{s}\n", .{std.mem.trimEnd(u8, evidence.written(), "\n")}) });
        }
    }
}
/// The owner fixtures hold the lock-ordering and erasure contracts; every later family reports code sizes.
fn owner(name: []const u8) bool {
    inline for (owner_names) |known| if (std.mem.eql(u8, name, known)) return true;
    return false;
}
fn reported(name: []const u8) bool {
    inline for (.{ "a67_", "gaps_", "state_", "scope_" }) |prefix| if (std.mem.startsWith(u8, name, prefix)) return true;
    return false;
}
pub fn alias(a: std.mem.Allocator, ir: []const u8, name: []const u8) ![]const u8 {
    const marker = try a.print("@{s} = alias ", .{name});
    const start = std.mem.find(u8, ir, marker) orelse {
        _ = try function(a, ir, name);
        return name;
    };
    const end = std.mem.findScalarPos(u8, ir, start, '\n') orelse return error.MalformedIr;
    const line = ir[start..end];
    const at = std.mem.find(u8, line, ", ptr @") orelse return error.MalformedAlias;
    return line[at + 7 ..];
}
pub fn function(a: std.mem.Allocator, ir: []const u8, name: []const u8) ![]const u8 {
    const marker = try a.print("@{s}(", .{name});
    var lines = std.mem.splitScalar(u8, ir, '\n');
    var body: std.Io.Writer.Allocating = .init(a);
    var found = false;
    while (lines.next()) |line| {
        if (!found) {
            if (!std.mem.startsWith(u8, line, "define ") or std.mem.find(u8, line, marker) == null) continue;
            found = true;
        }
        try body.writer.print("{s}\n", .{line});
        if (std.mem.eql(u8, line, "}")) return body.written();
    }
    return error.MissingEmittedFunction;
}

/// Writes one operand. A reference to a data label stands for the bytes behind it, so two tables with the
/// same contents are the same table whatever they are called.
fn operand(a: std.mem.Allocator, writer: *std.Io.Writer, text: []const u8, token: []const u8) !void {
    if (std.mem.find(u8, token, ".L")) |at| {
        var end = at + 2;
        while (end < token.len and (std.ascii.isAlphanumeric(token[end]) or token[end] == '_' or token[end] == '.' or token[end] == '$')) end += 1;
        if (try contents(a, text, token[at..end])) |bytes| return writer.print(" {s}<{s}>{s}", .{ token[0..at], bytes, token[end..] });
    }
    try writer.print(" {s}", .{token});
}

/// The bytes of a label that is plain data, written out in hex, or null when it is not.
fn contents(a: std.mem.Allocator, text: []const u8, label: []const u8) !?[]const u8 {
    const marker = try a.print("\n{s}:\n", .{label});
    const start = std.mem.find(u8, text, marker) orelse return null;
    var bytes: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text[start + marker.len ..], '\n');
    // Data ends at its `.size`, or for a constant-pool entry at the first line that is not data.
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (std.mem.startsWith(u8, line, ".size")) break;
        if (!try directive(a, &bytes, line)) {
            if (bytes.items.len == 0) return null;
            break;
        }
    } else return null;
    var hex: std.Io.Writer.Allocating = .init(a);
    for (bytes.items) |byte| try hex.writer.print("{x:0>2}", .{byte});
    return hex.written();
}

/// Appends the bytes one data directive stands for; false for anything that is not plain data.
fn directive(a: std.mem.Allocator, bytes: *std.ArrayList(u8), line: []const u8) !bool {
    if (line.len == 0 or line[0] != '.') return false;
    const space = std.mem.findAny(u8, line, " \t") orelse return false;
    const name = line[0..space];
    const rest = std.mem.trim(u8, line[space..], " \t");
    if (std.mem.eql(u8, name, ".ascii") or std.mem.eql(u8, name, ".asciz") or std.mem.eql(u8, name, ".string")) {
        if (rest.len < 2 or rest[0] != '"' or rest[rest.len - 1] != '"') return false;
        var i: usize = 1;
        while (i < rest.len - 1) : (i += 1) {
            if (rest[i] != '\\') {
                try bytes.append(a, rest[i]);
                continue;
            }
            i += 1;
            if (i >= rest.len - 1) return false;
            if (rest[i] >= '0' and rest[i] <= '7') {
                var value: u16 = 0;
                var digits: usize = 0;
                while (digits < 3 and i < rest.len - 1 and rest[i] >= '0' and rest[i] <= '7') : (digits += 1) {
                    value = value * 8 + (rest[i] - '0');
                    i += 1;
                }
                i -= 1;
                try bytes.append(a, @truncate(value));
            } else try bytes.append(a, switch (rest[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                'b' => 8,
                'f' => 12,
                else => rest[i],
            });
        }
        if (!std.mem.eql(u8, name, ".ascii")) try bytes.append(a, 0);
        return true;
    }
    if (std.mem.eql(u8, name, ".zero") or std.mem.eql(u8, name, ".space") or std.mem.eql(u8, name, ".fill")) {
        var parts = std.mem.tokenizeAny(u8, rest, ", ");
        const count = std.fmt.parseInt(usize, parts.next() orelse return false, 0) catch return false;
        const fill = if (parts.next()) |value| std.fmt.parseInt(u8, value, 0) catch return false else 0;
        try bytes.appendNTimes(a, fill, count);
        return true;
    }
    const width: usize = if (std.mem.eql(u8, name, ".byte")) 1 else if (std.mem.eql(u8, name, ".short") or std.mem.eql(u8, name, ".hword") or std.mem.eql(u8, name, ".2byte")) 2 else if (std.mem.eql(u8, name, ".long") or std.mem.eql(u8, name, ".word") or std.mem.eql(u8, name, ".4byte")) 4 else if (std.mem.eql(u8, name, ".quad") or std.mem.eql(u8, name, ".xword") or std.mem.eql(u8, name, ".8byte")) 8 else return false;
    var values = std.mem.tokenizeAny(u8, rest, ", ");
    while (values.next()) |value| {
        const number = std.fmt.parseInt(i64, value, 0) catch return false;
        const bits: u64 = @bitCast(number);
        for (0..width) |i| try bytes.append(a, @truncate(bits >> @intCast(8 * i)));
    }
    return true;
}

pub fn instructions(a: std.mem.Allocator, text: []const u8, name: []const u8, target: []const u8) ![]const u8 {
    const marker = try a.print(".L{s}:", .{name});
    const start = std.mem.find(u8, text, marker) orelse std.mem.find(u8, text, try a.print("\n{s}:", .{name})) orelse return error.MissingAssemblyFunction;
    const end = std.mem.findPos(u8, text, start, ".size") orelse return error.MissingAssemblySize;
    const body = text[start..end];
    var labels: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (std.mem.endsWith(u8, line, ":")) try labels.append(a, line[0 .. line.len - 1]);
    }
    var output: std.Io.Writer.Allocating = .init(a);
    lines.reset();
    while (lines.next()) |raw| {
        const comment = if (std.mem.startsWith(u8, target, "x86")) "#" else "//";
        const at = std.mem.find(u8, raw, comment) orelse raw.len;
        const line = std.mem.trim(u8, raw[0..at], " \t");
        if (line.len == 0 or line[0] == '.' or std.mem.endsWith(u8, line, ":")) continue;
        var tokens = std.mem.tokenizeAny(u8, line, " \t,");
        while (tokens.next()) |token| {
            var local = false;
            for (labels.items, 0..) |label, i| {
                if (std.mem.eql(u8, token, label)) {
                    try output.writer.print(" label{d}", .{i});
                    local = true;
                    break;
                }
            }
            if (!local) try operand(a, &output.writer, text, token);
        }
        try output.writer.writeByte('\n');
    }
    return output.written();
}

// The compiler emits little-endian ELF64 for the two fixed Linux target fixtures.
fn integer(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
pub fn symbolSize(object: []const u8, name: []const u8) !u64 {
    if (!std.mem.eql(u8, object[0..4], "\x7fELF") or object[4] != 2 or object[5] != 1) return error.ExpectedElf64Little;
    const sections = integer(u64, object, 40);
    const stride = integer(u16, object, 58);
    const count = integer(u16, object, 60);
    for (0..count) |i| {
        const section = sections + i * stride;
        if (integer(u32, object, section + 4) != 2) continue; // SHT_SYMTAB
        const offset = integer(u64, object, section + 24);
        const len = integer(u64, object, section + 32);
        const entry = integer(u64, object, section + 56);
        const strings = sections + integer(u32, object, section + 40) * stride;
        const string_offset = integer(u64, object, strings + 24);
        var cursor = offset;
        while (cursor < offset + len) : (cursor += entry) {
            const start = string_offset + integer(u32, object, cursor);
            const end = std.mem.findScalarPos(u8, object, start, 0) orelse return error.MalformedSymbol;
            if (std.mem.eql(u8, object[start..end], name)) return integer(u64, object, cursor + 16);
        }
    }
    return error.MissingObjectSymbol;
}

pub fn exportName(a: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    try out.writer.writeAll(prefix);
    var parts = std.mem.splitScalar(u8, name, '_');
    while (parts.next()) |part| {
        try out.writer.writeByte(std.ascii.toUpper(part[0]));
        try out.writer.writeAll(part[1..]);
    }
    return out.written();
}

// LLVM's machine-function merger can create assembly aliases absent from LLVM IR.
pub fn assemblyAlias(a: std.mem.Allocator, assembly: []const u8, name: []const u8) ![]const u8 {
    const marker = try a.print("\n{s} = ", .{name});
    const start = std.mem.find(u8, assembly, marker) orelse return name;
    const begin = start + marker.len;
    const end = std.mem.findScalarPos(u8, assembly, begin, '\n') orelse return error.MalformedAlias;
    const value = assembly[begin..end];
    return if (std.mem.startsWith(u8, value, ".L")) value[2..] else value;
}
