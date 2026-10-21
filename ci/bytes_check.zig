//! Required all-mode rejection of an overlapping move; no live station turns.
//! The build compiles the contract program in each mode and passes the binaries
//! in the order of `modes`; it compiles the portable byte owner too.
const std = @import("std");
const modes = [_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast" };
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 1 + modes.len) return error.ContractBinariesRequired;
    for (args[1..]) |binary| {
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{binary}, .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term == .exited and result.term.exited == 0) return error.OverlappingMoveAccepted;
        if (std.mem.find(u8, result.stderr, "@memcpy arguments alias") == null) return error.UnexpectedMoveFailure;
    }
}
