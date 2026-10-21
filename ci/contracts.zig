//! Required release failures; the raw integer ABI. The build compiles the
//! contract program in each mode and passes the binaries in the order of
//! `modes`, after the Zig the ABI check runs; it compiles the portable scalar
//! layouts (32-bit/wasm/freestanding) too.
const std = @import("std");
const modes = [_][]const u8{ "ReleaseSafe", "ReleaseFast" };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2 + modes.len) return error.ContractBinariesRequired;
    for (args[2..]) |binary| {
        for ([_][]const u8{ "pre", "post", "invariant", "never" }) |name| {
            const run = try std.process.run(init.gpa, init.io, .{ .argv = &.{ binary, name }, .stderr_limit = .limited(16384) });
            defer init.gpa.free(run.stdout);
            defer init.gpa.free(run.stderr);
            if (run.term == .exited and run.term.exited == 0) return error.RequiredContractStripped;
            if (std.mem.find(u8, run.stderr, "a3 required contract") == null) return error.UnexpectedContractFailure;
        }
    }
    const abi = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "run", "ci/abi_check.zig", "--", args[1] }, .stderr_limit = .limited(16384) });
    defer init.gpa.free(abi.stdout);
    defer init.gpa.free(abi.stderr);
    var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
    try out.interface.writeAll(abi.stderr);
    if (abi.term != .exited or abi.term.exited != 0) return error.RawIntegerAbiRejected;
}
