//! Required all-mode safety, checked-mode identity and Debug diagnostic contracts.
const std = @import("std");
const builtin = @import("builtin");
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    try std.Io.Dir.cwd().createDirPath(init.io, ".zig-cache/a67");
    for ([_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
        const binary = try arena.print(".zig-cache/a67/contracts-{s}{s}", .{ mode, if (builtin.os.tag == .windows) ".exe" else "" });
        const compiled = try std.process.run(gpa, init.io, .{ .argv = &.{ args[1], "build-exe", try arena.print("-O{s}", .{mode}), "--dep", "aegis", "-Mroot=ci/a67_contract.zig", "-Maegis=src/root.zig", try arena.print("-femit-bin={s}", .{binary}) }, .stderr_limit = .limited(16384) });
        defer gpa.free(compiled.stdout);
        defer gpa.free(compiled.stderr);
        if (compiled.term != .exited or compiled.term.exited != 0) {
            var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
            try out.interface.writeAll(compiled.stderr);
            return error.ContractCompilationFailed;
        }
        const checked = std.mem.eql(u8, mode, "Debug") or std.mem.eql(u8, mode, "ReleaseSafe");
        const debug = std.mem.eql(u8, mode, "Debug");
        const cases = [_][2][]const u8{ .{ "confined-access", "Confined accessed" }, .{ "confined-handoff", "Confined accessed" }, .{ "association", "condition used with a different owner" }, .{ "budget", "budget reservation underflow" }, .{ "order", "SameOwner" }, .{ "once", "recursive Once initializer" }, .{ "owned", "assertion failure" }, .{ "must-use", "required outcome inspection" } };
        for (cases, 0..) |case, index| {
            if (index >= 4 and !debug) continue;
            const must_fail = if (index < 2) checked else true;
            const result = try std.process.run(gpa, init.io, .{ .argv = &.{ binary, case[0] }, .stderr_limit = .limited(16384) });
            defer gpa.free(result.stdout);
            defer gpa.free(result.stderr);
            const succeeded = result.term == .exited and result.term.exited == 0;
            if (must_fail == succeeded) return error.ModeContractMismatch;
            if (must_fail and std.mem.find(u8, result.stderr, case[1]) == null) {
                var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
                try out.interface.writeAll(result.stderr);
                return error.UnexpectedContractFailure;
            }
        }
    }
    for ([_][]const u8{ "x86-linux-gnu", "wasm32-freestanding", "aarch64-freestanding" }) |target| {
        for ([_][]const u8{ "ReleaseSafe", "ReleaseFast" }) |mode| {
            const compiled = try std.process.run(gpa, init.io, .{ .argv = &.{ args[1], "build-obj", try arena.print("-O{s}", .{mode}), "-target", target, "--dep", "aegis", "-Mroot=ci/a67_values.zig", "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(16384) });
            defer gpa.free(compiled.stdout);
            defer gpa.free(compiled.stderr);
            if (compiled.term != .exited or compiled.term.exited != 0) {
                var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
                try out.interface.writeAll(compiled.stderr);
                return error.PortableA67CompilationFailed;
            }
        }
    }
}
