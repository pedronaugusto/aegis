//! A5 unsupported-profile and explicit-reveal/format compile contracts.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.ZigExecutableRequired;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/a5-negative");
    const cases = .{
        .{ "const x = c.selectInt(u9, 0, 1);", "8/16/32/64-bit" },
        .{ "const x = c.selectInt(u128, 0, 1);", "8/16/32/64-bit" },
        .{ "const x = c.selectInt(u0, 0, 0);", "8/16/32/64-bit" },
        .{ "const x = c.selectInt(f32, 0, 1);", "fixed-width integer" },
        .{ "const x = c.declassify(\"\");", "nonempty reason" },
        .{ "const x = c.declassify(\"   \");", "nonempty reason" },
        .{ "const x: bool = c;", "expected type 'bool'" },
        .{ "const x = c.selectInt(u64, 0, 1); if (c) return 1;", "expected type 'bool'" },
        .{ "var w = std.Io.Writer.Discarding.init(&.{}); const x = w.writer.print(\"{f}\", .{c}) catch 0;", "ChoiceNotFormattable" },
    };
    inline for (cases, 0..) |case, i| {
        const path = try a.print(".zig-cache/a5-negative/{d}.zig", .{i});
        const code = try a.print("const std = @import(\"std\");\nconst s = @import(\"aegis\").secret;\nexport fn run(a: *const [1]u8,b: *const [1]u8) u64 {{ const c = s.equal(1,a,b); {s} std.mem.doNotOptimizeAway(x); return 0; }}\n", .{case[0]});
        try dir.writeFile(init.io, .{ .sub_path = path, .data = code });
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast" }) |mode| {
            try rejected(init, args[1], path, "aarch64-linux-gnu", "baseline", mode, "-fllvm", case[1]);
        }
    }
    // Every build compiles the kernels; `Choice.audited` says whether it is one check-choices
    // inspects. Outside the list (a target, CPU, backend or mitigation level not checked) the
    // kernels compile and the flag is false.
    const path = ".zig-cache/a5-negative/profile.zig";
    const body = "const s = @import(\"aegis\").secret; export fn run(a: *const [1]u8,b: *const [1]u8) u64 { return @intFromBool(s.equal(1,a,b).declassify(\"public test verdict\")); }\n";
    try dir.writeFile(init.io, .{ .sub_path = path, .data = body ++ "comptime { if (s.Choice.audited) @compileError(\"unexpectedly audited\"); }\n" });
    for ([_][]const u8{ "x86-linux-musl", "wasm32-wasi", "aarch64-freestanding", "riscv64-linux-gnu" }) |target| {
        try accepted(init, args[1], path, target, "baseline", "ReleaseFast", "-fllvm");
    }
    try accepted(init, args[1], path, "x86_64-linux-gnu", "znver4", "ReleaseFast", "-fllvm");
    try accepted(init, args[1], path, "aarch64-macos", "apple_m3-sha3", "ReleaseFast", "-fllvm");
    try accepted(init, args[1], path, "x86_64-linux-gnu", "baseline", "Debug", "-fno-llvm");
    const none = "const std = @import(\"std\"); pub const std_options: std.Options = .{.side_channels_mitigations=.none}; ";
    try dir.writeFile(init.io, .{ .sub_path = path, .data = none ++ body ++ "comptime { if (s.Choice.audited) @compileError(\"unexpectedly audited\"); }\n" });
    try accepted(init, args[1], path, "aarch64-linux-gnu", "baseline", "ReleaseFast", "-fllvm");
    // Each listed profile is audited.
    try dir.writeFile(init.io, .{ .sub_path = path, .data = body ++ "comptime { if (!s.Choice.audited) @compileError(\"listed profile not audited\"); }\n" });
    for (@import("aegis").secret.audited_profiles.all) |profile| {
        try accepted(init, args[1], path, profile.target, profile.cpu, "ReleaseFast", "-fllvm");
    }
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("A5: compiler contracts passed (rejections, unaudited builds compile, listed builds audited)\n");
    try out.interface.flush();
}
fn rejected(init: std.process.Init, zig: []const u8, path: []const u8, target: []const u8, cpu: []const u8, mode: []const u8, backend: []const u8, message: []const u8) !void {
    const a = init.arena.allocator();
    const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ zig, "build-obj", try a.print("-O{s}", .{mode}), "-target", target, try a.print("-mcpu={s}", .{cpu}), backend, "--dep", "aegis", try a.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(32768) });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited == 0 or std.mem.find(u8, result.stderr, message) == null) {
        var err = std.Io.File.stderr().writer(init.io, &.{});
        try err.interface.print("{s} {s} {s} {s} exit={any} expected={s}\n", .{ path, target, cpu, mode, result.term, message });
        try err.interface.writeAll(result.stderr);
        try err.interface.flush();
        return error.ChoiceContractNotDiagnosed;
    }
}
fn accepted(init: std.process.Init, zig: []const u8, path: []const u8, target: []const u8, cpu: []const u8, mode: []const u8, backend: []const u8) !void {
    const a = init.arena.allocator();
    const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ zig, "build-obj", try a.print("-O{s}", .{mode}), "-target", target, try a.print("-mcpu={s}", .{cpu}), backend, "--dep", "aegis", try a.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(32768) });
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        var err = std.Io.File.stderr().writer(init.io, &.{});
        try err.interface.print("{s} {s} {s} {s}: expected to compile\n", .{ target, cpu, mode, backend });
        try err.interface.writeAll(result.stderr);
        try err.interface.flush();
        return error.ChoiceProfileContract;
    }
}
