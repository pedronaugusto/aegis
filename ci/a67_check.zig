//! Required all-mode safety, checked-mode identity and Debug diagnostic contracts.
const std = @import("std");
const builtin = @import("builtin");
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    try std.Io.Dir.cwd().createDirPath(init.io, ".zig-cache/a67");
    for ([_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" }) |mode| {
        const binary = try arena.print(".zig-cache/a67/contracts-{s}{s}", .{ mode, if (builtin.target.os.tag == .windows) ".exe" else "" });
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
        const When = enum { checked, always, debug };
        const cases = [_]struct { name: []const u8, message: []const u8, when: When, safe_message: []const u8 = "" }{
            .{ .name = "confined-access", .message = "Confined accessed", .when = .checked },
            .{ .name = "confined-handoff", .message = "Confined accessed", .when = .checked },
            .{ .name = "association", .message = "condition used with a different owner", .when = .always },
            .{ .name = "budget", .message = "budget reservation underflow", .when = .always },
            .{ .name = "shared-overflow", .message = "shared owner handle count overflow", .when = .always },
            .{ .name = "order", .message = "SameOwner", .when = .debug },
            .{ .name = "once", .message = "recursive Once initializer", .when = .debug },
            .{ .name = "owned", .message = "assertion failure", .when = .debug },
            .{ .name = "must-use", .message = "required outcome inspection", .when = .debug },
            .{ .name = "shared-twice", .message = "assertion failure", .when = .debug },
            // A failed assertion reads differently once Debug's own panic handler is gone.
            .{ .name = "teardown-held", .message = "assertion failure", .when = .checked, .safe_message = "reached unreachable code" },
        };
        for (cases) |case| {
            if (case.when == .debug and !debug) continue;
            const must_fail = switch (case.when) {
                .checked => checked,
                .always, .debug => true,
            };
            const result = try std.process.run(gpa, init.io, .{ .argv = &.{ binary, case.name }, .stderr_limit = .limited(16384) });
            defer gpa.free(result.stdout);
            defer gpa.free(result.stderr);
            const succeeded = result.term == .exited and result.term.exited == 0;
            if (must_fail == succeeded) return error.ModeContractMismatch;
            const expected = if (!debug and case.safe_message.len != 0) case.safe_message else case.message;
            if (must_fail and std.mem.find(u8, result.stderr, expected) == null) {
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
