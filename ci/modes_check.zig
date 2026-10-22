//! Runs the mode matrix (ci/modes.zig). The build compiles the program in each mode and
//! passes the binaries in the order of `modes`; every case must stop, printing its message,
//! exactly in the builds its `when` names, and run to the end in the others.
const std = @import("std");
const matrix = @import("modes.zig");

const Mode = enum { debug, safe, fast, small };
const modes = [_]Mode{ .debug, .safe, .fast, .small };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 1 + modes.len) return error.ContractBinariesRequired;
    var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
    for (modes, args[1..]) |mode, binary| {
        for (matrix.cases) |case| {
            const stops = switch (case.when) {
                .debug => mode == .debug,
                .checked => mode == .debug or mode == .safe,
                .always => true,
            };
            if (!stops and !case.runs_unchecked) continue;
            const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ binary, case.name }, .stderr_limit = .limited(16384) });
            defer init.gpa.free(result.stdout);
            defer init.gpa.free(result.stderr);
            const ran = result.term == .exited and result.term.exited == 0;
            if (stops == ran) {
                try out.interface.print("{s} {s} {t}: expected {s}\n{s}", .{ case.module, case.name, mode, if (stops) "a stop" else "no stop", result.stderr });
                return error.ModeContractMismatch;
            }
            if (stops and std.mem.find(u8, result.stderr, case.message) == null) {
                try out.interface.print("{s} {s} {t}: expected \"{s}\"\n{s}", .{ case.module, case.name, mode, case.message, result.stderr });
                return error.UnexpectedContractFailure;
            }
        }
    }
    try out.interface.print("mode matrix: {d} cases in 4 modes\n", .{matrix.cases.len});
}
