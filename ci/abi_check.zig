//! Deterministic raw-prototype ABI parity on every configured cross target.
const std = @import("std");
const builtin = @import("builtin");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stderr().writerStreaming(init.io, &buffer);
    defer out.interface.flush() catch {}; // glint-ignore: Z026 -- stderr is the only channel a failed flush could be reported on
    const args = try init.minimal.args.toSlice(a);
    const source = if (args.len > 2 and std.mem.eql(u8, args[2], "--before")) "-Maegis=.zig-cache/a3-before/src/root.zig" else "-Maegis=src/root.zig";
    const audit = args.len > 2 and std.mem.eql(u8, args[2], "--audit");
    var total_mismatches: usize = 0;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/abi");
    const targets = [_][]const u8{ "x86-linux-gnu", "x86_64-linux-gnu", "x86_64-linux-musl", "aarch64-linux-gnu", "x86_64-windows-gnu", "aarch64-windows-gnu", "x86_64-macos", "aarch64-macos", "wasm32-freestanding" };
    const manifest = try dir.readFileAlloc(init.io, "ci/workflow.json", a, .limited(65536));
    const config = try std.json.parseFromSlice(struct { targets: []const []const u8 }, a, manifest, .{ .ignore_unknown_fields = true });
    defer config.deinit();
    for (config.value.targets) |configured| {
        var covered = false;
        for (targets) |target| covered = covered or std.mem.eql(u8, configured, target);
        if (!covered) return error.ConfiguredAbiTargetMissing;
    }
    for (targets) |target| {
        const stem = try a.print(".zig-cache/abi/{s}", .{target});
        try run(init, &.{ args[1], "build-obj", "-OReleaseFast", "-fllvm", "-fstrip", "-target", target, "--dep", "aegis", "-Mroot=ci/abi.zig", source, try a.print("-femit-bin={s}.o", .{stem}), try a.print("-femit-llvm-ir={s}.ll", .{stem}) });
        try run(init, &.{ args[1], "build-obj", "-OReleaseFast", "-fllvm", "-fstrip", "-target", target, "ci/abi_raw.zig", try a.print("-femit-bin={s}-raw.o", .{stem}) });
        // Preserve the raw-Zig regression and also compile genuinely foreign C
        // prototypes on every ABI profile, including 32-bit x86 and wasm.
        try run(init, &.{ args[1], "cc", "-target", target, "-O2", "-ffreestanding", "-fno-stack-protector", "-c", "ci/abi_raw.c", "-o", try a.print("{s}-c.o", .{stem}) });
        const ir = try dir.readFileAlloc(init.io, try a.print("{s}.ll", .{stem}), a, .limited(16 * 1024 * 1024));
        var lines = std.mem.splitScalar(u8, ir, '\n');
        var count: usize = 0;
        var mismatches: usize = 0;
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "@typed_")) continue;
            const end = std.mem.find(u8, line, " = alias ") orelse return error.ExpectedAnalyzedCaller;
            const suffix = line[7..end];
            const baseline = try a.print("@baseline_{s} = alias ", .{suffix});
            const at = std.mem.find(u8, ir, baseline) orelse return error.MissingRawPrototypeCaller;
            const rest = ir[at + baseline.len ..];
            const finish = std.mem.findScalar(u8, rest, '\n') orelse return error.MalformedIr;
            if (!std.mem.eql(u8, line[end + 9 ..], rest[0..finish])) {
                if (mismatches == 0) try out.interface.print("{s}: raw integer ABI mismatch: {s}\n{s}\n{s}{s}\n", .{ target, suffix, line, baseline, rest[0..finish] });
                mismatches += 1;
                if (!audit) return error.RawIntegerAbiMismatch;
            }
            count += 1;
        }
        if (count != 1010) return error.MissingAbiFactories;
        total_mismatches += mismatches;
        try out.interface.print("mismatched pairs={d}\n", .{mismatches});
        try out.interface.print("{s}: 505 raw-integer argument/return pairs + 505 record-field pairs: analyzed callers (cross codegen only)\n", .{target});
    }
    try run(init, &.{ args[1], "build-obj", "-OReleaseFast", "-fllvm", "ci/abi_raw.zig", "-femit-bin=.zig-cache/abi/native-raw.o" });
    const binary = try a.print(".zig-cache/abi/native{s}", .{if (builtin.target.os.tag == .windows) ".exe" else ""});
    try run(init, &.{ args[1], "build-exe", "-OReleaseFast", "-fllvm", ".zig-cache/abi/native-raw.o", "--dep", "aegis", "-Mroot=ci/abi_native.zig", source, try a.print("-femit-bin={s}", .{binary}) });
    try run(init, &.{binary});
    try out.interface.print("native {s}-{s}: separately linked raw integer calls and record fields passed\n", .{ @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag) });
    try run(init, &.{ args[1], "cc", "-O2", "-ffreestanding", "-fno-stack-protector", "-c", "ci/abi_raw.c", "-o", ".zig-cache/abi/native-c.o" });
    const c_binary = try a.print(".zig-cache/abi/native-c{s}", .{if (builtin.target.os.tag == .windows) ".exe" else ""});
    try run(init, &.{ args[1], "build-exe", "-OReleaseFast", "-fllvm", ".zig-cache/abi/native-c.o", "--dep", "aegis", "-Mroot=ci/abi_native.zig", source, try a.print("-femit-bin={s}", .{c_binary}) });
    try run(init, &.{c_binary});
    try out.interface.print("native {s}-{s}: independently compiled C integer calls and record fields passed\n", .{ @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag) });
    if (total_mismatches != 0) return error.RawIntegerAbiMismatch;
}
fn run(init: std.process.Init, argv: []const []const u8) !void {
    const result = try std.process.run(init.gpa, init.io, .{ .argv = argv, .stderr_limit = .limited(16384) });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
        try out.interface.writeAll(result.stderr);
        return error.AbiCommandFailed;
    }
}
