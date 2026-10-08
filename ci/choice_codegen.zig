//! Deterministic A5 enclosing-caller lowering/cost gate. Raw evidence is private.
const std = @import("std");
const cases = @import("choice_callers.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const dir = std.Io.Dir.cwd();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2 or args.len > 3) return error.ZigExecutableRequired;
    const destination = if (args.len == 3) args[2] else ".zig-cache/a5-proof";
    try dir.createDirPath(init.io, destination);
    var report = std.Io.Writer.Allocating.init(a);
    for ([_][]const u8{ "x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-linux-musl", "x86_64-windows-gnu", "aarch64-windows-gnu", "x86_64-macos", "aarch64-macos" }) |target| {
        for ([_][]const u8{ "Debug", "ReleaseFast", "ReleaseSafe", "ReleaseSmall" }) |mode| {
            for ([_][]const u8{ "basic", "medium", "full" }) |mitigation| {
                const profile = try a.print("{s}/profile.zig", .{destination});
                try dir.writeFile(init.io, .{ .sub_path = profile, .data = try a.print("const std = @import(\"std\");\npub const mitigation: std.crypto.SideChannelsMitigations = .{s};\n", .{mitigation}) });
                const stem = try a.print("{s}/{s}-{s}-{s}", .{ destination, target, mode, mitigation });
                const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", try a.print("-O{s}", .{mode}), "-target", target, "-mcpu=baseline", "-fllvm", "-fstrip", "--dep", "aegis", "--dep", "profile", "-Mroot=ci/choice_parity.zig", "-Maegis=src/root.zig", try a.print("-Mprofile={s}", .{profile}), try a.print("-femit-llvm-ir={s}.ll", .{stem}), try a.print("-femit-asm={s}.s", .{stem}), "-fno-emit-bin" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(65536) });
                defer init.gpa.free(result.stdout);
                defer init.gpa.free(result.stderr);
                if (result.term != .exited or result.term.exited != 0) {
                    var err = std.Io.File.stderr().writer(init.io, &.{});
                    try err.interface.writeAll(result.stderr);
                    return error.CallerCompilationFailed;
                }
                var profile_arena = std.heap.ArenaAllocator.init(init.gpa);
                defer profile_arena.deinit();
                const scratch = profile_arena.allocator();
                const ir = try dir.readFileAlloc(init.io, try a.print("{s}.ll", .{stem}), scratch, .limited(64 * 1024 * 1024));
                const assembly = try dir.readFileAlloc(init.io, try a.print("{s}.s", .{stem}), scratch, .limited(64 * 1024 * 1024));
                inline for (.{ "leakBranch", "leakIndex", "leakCall" }) |unsafe_name| {
                    const unsafe_body = try function(scratch, ir, try alias(a, ir, unsafe_name));
                    var diagnosed = false;
                    audit(scratch, unsafe_body) catch |err| {
                        if (err != error.SecretDependentControlOrAddress and err != error.UninlinedSecretHelper) return err;
                        diagnosed = true;
                    };
                    if (!diagnosed) return error.UnsafeCallerNotDetected;
                }
                inline for (cases.names) |name| {
                    const bn = try exportName(a, "baseline", name);
                    const wn = try exportName(a, "wrapper", name);
                    const ba = try assemblyAlias(a, assembly, bn, target);
                    const wa = try assemblyAlias(a, assembly, wn, target);
                    const bi = try instructions(scratch, assembly, ba, target);
                    const wi = try instructions(scratch, assembly, wa, target);
                    if (!std.mem.eql(u8, mode, "Debug") and !std.mem.eql(u8, bi, wi)) {
                        var err = std.Io.File.stderr().writer(init.io, &.{});
                        try err.interface.print("{s} {s} {s} {s}: caller instruction mismatch\n", .{ target, mode, mitigation, name });
                        return error.CallerCostMismatch;
                    }
                    // Retain the exact enclosing bodies; semantic taint review is a separate gate.
                    const wb = try function(scratch, ir, try alias(a, ir, wn));
                    try audit(scratch, wb);
                    try report.writer.print("{s} {s} {s} {s} checked-caller bytes-of-normalized-text={d} caller-ir={d}\n", .{ target, mode, mitigation, name, wi.len, wb.len });
                }
            }
        }
    }
    try dir.writeFile(init.io, .{ .sub_path = try a.print("{s}/parity.txt", .{destination}), .data = report.written() });
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A5 caller parity profiles completed\n");
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
    const symbol = if (std.mem.find(u8, target, "macos") != null and !std.mem.startsWith(u8, name, "l_")) try a.print("_{s}", .{name}) else name;
    const start = std.mem.find(u8, text, try a.print("\n{s}:", .{symbol})) orelse std.mem.find(u8, text, try a.print("\n.L{s}:", .{symbol})) orelse return error.MissingAssemblyFunction;
    var end = text.len;
    for ([_][]const u8{ ".Lfunc_end", "Lfunc_end", ".seh_endproc", ".cfi_endproc", "\n\t.def\t", "\n\t.globl\t", "\n\t.section" }) |marker| {
        if (std.mem.findPos(u8, text, start, marker)) |at| end = @min(end, at);
    }
    if (end == text.len) return error.MissingAssemblySize;
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
fn assemblyAlias(a: std.mem.Allocator, assembly: []const u8, name: []const u8, target: []const u8) ![]const u8 {
    const symbol = if (std.mem.find(u8, target, "macos") != null and !std.mem.startsWith(u8, name, "l_")) try a.print("_{s}", .{name}) else name;
    const marker = try a.print("\n{s} = ", .{symbol});
    const start = std.mem.find(u8, assembly, marker) orelse return name;
    const begin = start + marker.len;
    const end = std.mem.findScalarPos(u8, assembly, begin, '\n') orelse return error.MalformedAlias;
    const value = assembly[begin..end];
    if (std.mem.startsWith(u8, value, ".L")) return value[2..];
    if (std.mem.startsWith(u8, value, "_")) return value[1..];
    return value;
}

// Conservative SSA taint check for optimized, fully inlined callers. All loads
// are secret-class data; arguments (length/endian/addresses) remain public.
// A secret value may not reach a branch, switch, select condition or GEP index.
// This is a regression detector for these fixtures, not a whole-program proof.
fn audit(a: std.mem.Allocator, body: []const u8) !void {
    var secret = std.StringHashMap(void).init(a);
    var memory = std.StringHashMap(void).init(a);
    var stored_pointers = std.StringHashMap(void).init(a);
    var roots = std.StringHashMap([]const u8).init(a);
    // Enclosing exported ABI: out, a, b are public addresses holding secret bytes.
    inline for (.{ "%0", "%1", "%2" }) |input| {
        try memory.put(input, {});
        try roots.put(input, input);
    }
    var lines = std.mem.splitScalar(u8, body, '\n');
    var changed = true;
    while (changed) {
        changed = false;
        lines.reset();
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t");
            if (std.mem.startsWith(u8, line, "define ")) continue;
            const eq = std.mem.find(u8, line, " = ");
            const lhs = if (eq) |i| line[0..i] else "";
            const rhs = if (eq) |i| line[i + 3 ..] else line;
            var refs = std.ArrayList([]const u8).empty;
            var words = std.mem.tokenizeAny(u8, rhs, " ,[]()\t");
            while (words.next()) |word| {
                if (std.mem.startsWith(u8, word, "%")) try refs.append(a, word);
            }
            const load = std.mem.startsWith(u8, rhs, "load ");
            const pointer = std.mem.startsWith(u8, rhs, "load ptr") or std.mem.startsWith(u8, rhs, "load volatile ptr") or std.mem.startsWith(u8, rhs, "getelementptr ") or std.mem.startsWith(u8, rhs, "phi ptr") or std.mem.startsWith(u8, rhs, "select i1");
            if (std.mem.startsWith(u8, rhs, "alloca ") and !roots.contains(lhs)) {
                try roots.put(lhs, lhs);
                changed = true;
            }
            if (std.mem.startsWith(u8, rhs, "store ") and refs.items.len >= 2) {
                const value = refs.items[0];
                const dest = refs.items[1];
                const root = roots.get(dest) orelse dest;
                const ptr_store = std.mem.startsWith(u8, rhs, "store ptr") or std.mem.startsWith(u8, rhs, "store volatile ptr");
                const source_root = roots.get(value) orelse value;
                const target = if (ptr_store) &stored_pointers else &memory;
                if ((if (ptr_store) memory.contains(source_root) else secret.contains(value)) and !target.contains(root)) {
                    try target.put(root, {});
                    changed = true;
                }
                continue;
            }
            if (eq == null) continue;
            var tainted = false;
            if (load and refs.items.len != 0) {
                const address = refs.items[0];
                const root = roots.get(address) orelse address;
                tainted = if (pointer) stored_pointers.contains(root) else memory.contains(root);
                if (pointer and tainted and !memory.contains(lhs)) {
                    try memory.put(lhs, {});
                    try roots.put(lhs, lhs);
                    changed = true;
                }
            } else if (!pointer) {
                for (refs.items) |ref| if (secret.contains(ref)) {
                    tainted = true;
                };
                // Address integers remain public even when the pointee holds secrets.
                if (std.mem.startsWith(u8, rhs, "ptrtoint ")) tainted = false;
            }
            if ((std.mem.startsWith(u8, rhs, "phi ptr") or std.mem.startsWith(u8, rhs, "select i1")) and !roots.contains(lhs)) {
                for (refs.items) |ref| {
                    if (memory.contains(roots.get(ref) orelse ref)) {
                        try memory.put(lhs, {});
                        try roots.put(lhs, lhs);
                        changed = true;
                        break;
                    }
                }
            }
            if (std.mem.startsWith(u8, rhs, "getelementptr ") and refs.items.len != 0 and !roots.contains(lhs)) {
                try roots.put(lhs, roots.get(refs.items[0]) orelse refs.items[0]);
                changed = true;
            }
            if (tainted and !pointer and !secret.contains(lhs)) {
                try secret.put(lhs, {});
                changed = true;
            }
        }
    }
    lines.reset();
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        const eq = std.mem.find(u8, line, " = ");
        const rhs = if (eq) |i| line[i + 3 ..] else line;
        // These fixtures must inline the value kernels. A pointer argument to
        // an unresolved helper is not modeled by this intraprocedural detector.
        // Refuse that gap rather than crediting an empty caller body as audited.
        if (std.mem.find(u8, rhs, "call ") != null) {
            inline for (.{ "@choice_callers.", "@choice_parity.", "@constant_time.", "@choice_baseline." }) |prefix| {
                if (std.mem.find(u8, rhs, prefix) != null) return error.UninlinedSecretHelper;
            }
        }
        const branch = std.mem.startsWith(u8, rhs, "br i1 ") or std.mem.startsWith(u8, rhs, "switch ");
        const selected = std.mem.startsWith(u8, rhs, "select ");
        const indexed = std.mem.startsWith(u8, rhs, "getelementptr ");
        if (!branch and !selected and !indexed) continue;
        var words = std.mem.tokenizeAny(u8, rhs, " ,[]()\t");
        var n: usize = 0;
        while (words.next()) |word| : (n += 1) {
            if ((branch or selected) and n > 2) break;
            if (indexed and n < 4) continue;
            if (secret.contains(word)) {
                var err = std.Io.File.stderr().writer(std.Io.Threaded.global_single_threaded.io(), &.{});
                try err.interface.print("secret reached control/address: {s}\n", .{line});
                try err.interface.flush();
                return error.SecretDependentControlOrAddress;
            }
        }
    }
}
