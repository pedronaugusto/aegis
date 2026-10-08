//! Negative compilation must fail for the intended shape-validation reason.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ZigExecutableRequired;
    for ([_][]const u8{ "slice", "pointer", "aggregate", "optional", "union", "function", "nested", "resource", "format" }) |name| {
        const root = try init.arena.allocator().print("-Mroot=ci/negative/{s}.zig", .{name});
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", "--dep", "aegis", root, "-Maegis=src/root.zig", "-fno-emit-bin", "--cache-dir", ".zig-cache/negative", "--global-cache-dir", ".zig-cache/global" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited == 0) return error.UnsupportedShapeAccepted;
        const message = if (std.mem.eql(u8, name, "format")) "SecretNotFormattable" else "Secret requires";
        if (std.mem.find(u8, result.stderr, message) == null) return error.UnexpectedCompilationFailure;
    }
}
