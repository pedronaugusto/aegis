//! The raw integer ABI: typed calls against separately compiled raw-integer exports. The
//! build passes the Zig the check runs; it compiles the portable scalar layouts
//! (32-bit/wasm/freestanding) too.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ZigExecutableRequired;
    const abi = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "run", "ci/abi_check.zig", "--", args[1] }, .stderr_limit = .limited(16384) });
    defer init.gpa.free(abi.stdout);
    defer init.gpa.free(abi.stderr);
    var out = std.Io.File.stderr().writerStreaming(init.io, &.{});
    try out.interface.writeAll(abi.stderr);
    if (abi.term != .exited or abi.term.exited != 0) return error.RawIntegerAbiRejected;
}
