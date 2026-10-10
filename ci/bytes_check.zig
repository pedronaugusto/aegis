//! Required all-mode rejection of an overlapping move; no live station turns.
const std = @import("std");
const builtin = @import("builtin");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/a4-proof");
    for ([_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast" }) |mode| {
        const binary = try a.print(".zig-cache/a4-proof/move-{s}{s}", .{ mode, if (builtin.os.tag == .windows) ".exe" else "" });
        const compiled = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-exe", try a.print("-O{s}", .{mode}), "--dep", "aegis", "-Mroot=ci/bytes_contract.zig", "-Maegis=src/root.zig", try a.print("-femit-bin={s}", .{binary}) }, .stderr_limit = .limited(16384) });
        defer init.gpa.free(compiled.stdout);
        defer init.gpa.free(compiled.stderr);
        if (compiled.term != .exited or compiled.term.exited != 0) {
            var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
            try out.interface.writeAll(compiled.stderr);
            return error.MoveContractCompilationFailed;
        }
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{binary}, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term == .exited and result.term.exited == 0) return error.OverlappingMoveAccepted;
        if (std.mem.find(u8, result.stderr, "@memcpy arguments alias") == null) return error.UnexpectedMoveFailure;
    }
    for ([_][]const u8{ "x86-linux-gnu", "wasm32-freestanding", "aarch64-freestanding" }) |target| {
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", "-OReleaseFast", "-target", target, "--dep", "aegis", "-Mroot=ci/a4_contract.zig", "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
            try out.interface.writeAll(result.stderr);
            return error.PortableBytesCompilationFailed;
        }
    }
}
