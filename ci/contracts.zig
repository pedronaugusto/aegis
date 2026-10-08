//! Required release failures and portable scalar layout (32-bit/wasm/freestanding).
const builtin = @import("builtin");
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.ZigExecutableRequired;
    for ([_][]const u8{ "ReleaseSafe", "ReleaseFast" }) |mode| {
        const binary = try a.print(".zig-cache/contract-{s}{s}", .{ mode, if (builtin.os.tag == .windows) ".exe" else "" });
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-exe", try a.print("-O{s}", .{mode}), "--dep", "aegis", "-Mroot=ci/contract.zig", "-Maegis=src/root.zig", try a.print("-femit-bin={s}", .{binary}) }, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.writeAll(result.stderr);
            return error.ContractCompilationFailed;
        }
        for ([_][]const u8{ "pre", "post", "invariant" }) |name| {
            const run = try std.process.run(init.gpa, init.io, .{ .argv = &.{ binary, name }, .stderr_limit = .limited(16384) });
            defer init.gpa.free(run.stdout);
            defer init.gpa.free(run.stderr);
            if (run.term == .exited and run.term.exited == 0) return error.RequiredContractStripped;
            if (std.mem.find(u8, run.stderr, "a3 required contract") == null) return error.UnexpectedContractFailure;
        }
    }
    for ([_][]const u8{ "x86-linux-gnu", "wasm32-freestanding", "aarch64-freestanding" }) |target| {
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", "-OReleaseFast", "-target", target, "--dep", "aegis", "-Mroot=ci/scalars.zig", "-Maegis=src/root.zig", "-fno-emit-bin" }, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.writeAll(result.stderr);
            return error.PortableScalarCompilationFailed;
        }
    }
    for ([_][]const u8{ "x86_64-linux-gnu", "aarch64-linux-gnu", "x86-linux-gnu", "x86_64-windows-gnu", "aarch64-windows-gnu", "x86_64-macos", "aarch64-macos", "wasm32-freestanding" }) |target| {
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", "-OReleaseFast", "-target", target, "--dep", "aegis", "-Mroot=ci/abi.zig", "-Maegis=src/root.zig", try a.print("-femit-bin=.zig-cache/abi-{s}.o", .{target}) }, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.writeAll(result.stderr);
            return error.DirectScalarAbiRejected;
        }
    }
}
