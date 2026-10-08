//! Strict optimizer-equivalence gate: aliases or exact normalized instruction equality.
const std = @import("std");
const owner_names = [_][]const u8{ "secret_s32", "transfer_s32", "secret_s48", "transfer_s48", "secret_material", "transfer_material", "cleanup", "cleanup_material", "budget", "job", "increment" };
const numeric_names = [_][]const u8{ "numeric_add", "numeric_sub", "numeric_mul", "numeric_div", "numeric_rem", "numeric_shift", "numeric_saturating", "numeric_ranged", "numeric_cast", "numeric_identity", "numeric_counter", "numeric_count", "numeric_bits", "numeric_duration", "numeric_rounding", "numeric_instant", "numeric_invariant", "numeric_diagnostics", "numeric_encoding" };
const bytes_names = [_][]const u8{ "bytes_dead", "bytes_cleanup", "bytes_resize", "bytes_reserve", "bytes_move", "bytes_adopt_dead", "bytes_replace" };
const a67_names = [_][]const u8{ "a67_mutex", "a67_rw_read", "a67_rw_write", "a67_once_ready", "a67_once_cold", "a67_condition", "a67_array", "a67_queue", "a67_buffer", "a67_budget", "a67_owned", "a67_must_use", "a67_confined", "a67_ordered", "a67_ring_buffer", "a67_limit" };
const names = owner_names ++ numeric_names ++ bytes_names ++ a67_names;
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
                if (baseline_bytes != wrapper_bytes) {
                    var failure = std.Io.File.stderr().writer(init.io, &.{});
                    try failure.interface.print("{s} {s} {s}: code size {d}/{d}\n", .{ target, mode, name, baseline_bytes, wrapper_bytes });
                    return error.AbstractionCodeSizeMismatch;
                }
                if (std.mem.startsWith(u8, name, "a67_")) {
                    var numbers = std.Io.File.stdout().writerStreaming(init.io, &.{});
                    try numbers.interface.print("code,{s},{s},{s},{d},{d}\n", .{ name, target, mode, baseline_bytes, wrapper_bytes });
                }
                const emitted_base = try assemblyAlias(a, assembly, try exportName(a, "baseline", name));
                const emitted_wrap = try assemblyAlias(a, assembly, try exportName(a, "wrapper", name));
                const emitted = try instructions(a, assembly, emitted_base, target);
                if (!std.mem.eql(u8, emitted_base, emitted_wrap)) {
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
                } else if (!std.mem.startsWith(u8, name, "numeric_") and !std.mem.startsWith(u8, name, "a67_")) {
                    const acquire = if (std.mem.startsWith(u8, target, "x86")) std.mem.find(u8, body, "acquire monotonic") != null else std.mem.find(u8, body, "@llvm.aarch64.ldaxr") != null and std.mem.find(u8, body, "@llvm.aarch64.stxr") != null;
                    if (!acquire or std.mem.find(u8, body, "release") == null) return error.MissingLockOrdering;
                }
                try evidence.writer.print("## {s}\n\nSymbols → `{s}` / `{s}`; baseline/wrapper machine code {d}/{d} bytes.\n\n```asm\n{s}```\n\n```llvm\n{s}\n```\n\n", .{ name, base, wrap, baseline_bytes, wrapper_bytes, emitted, body });
            }
            if (record) try dir.writeFile(init.io, .{ .sub_path = try a.print(".zig-cache/parity/codegen-{s}-{s}.md", .{ target, mode }), .data = try a.print("{s}\n", .{std.mem.trimEnd(u8, evidence.written(), "\n")}) });
        }
    }
}
fn alias(a: std.mem.Allocator, ir: []const u8, name: []const u8) ![]const u8 {
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
fn function(a: std.mem.Allocator, ir: []const u8, name: []const u8) ![]const u8 {
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

fn instructions(a: std.mem.Allocator, text: []const u8, name: []const u8, target: []const u8) ![]const u8 {
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
            if (!local) try output.writer.print(" {s}", .{token});
        }
        try output.writer.writeByte('\n');
    }
    return output.written();
}

// The compiler emits little-endian ELF64 for the two fixed Linux target fixtures.
fn integer(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
fn symbolSize(object: []const u8, name: []const u8) !u64 {
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

fn exportName(a: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
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
fn assemblyAlias(a: std.mem.Allocator, assembly: []const u8, name: []const u8) ![]const u8 {
    const marker = try a.print("\n{s} = ", .{name});
    const start = std.mem.find(u8, assembly, marker) orelse return name;
    const begin = start + marker.len;
    const end = std.mem.findScalarPos(u8, assembly, begin, '\n') orelse return error.MalformedAlias;
    const value = assembly[begin..end];
    return if (std.mem.startsWith(u8, value, ".L")) value[2..] else value;
}
