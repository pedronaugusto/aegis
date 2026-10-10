const std = @import("std");
const aegis = @import("aegis");
// An external effect proves false pre/post/invariant actually fail-stop in release.
// Override panic only to keep subprocess output deterministic on every host.
pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    std.process.fatal("{s}", .{message});
}
pub fn main(init: std.process.Init) void {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch @panic("args");
    const name = if (args.len > 1) args[1] else "invariant";
    if (std.mem.eql(u8, name, "never")) aegis.assert.never("a3 required contract") else if (std.mem.eql(u8, name, "pre")) aegis.assert.pre(false, "a3 required contract") else if (std.mem.eql(u8, name, "post")) aegis.assert.post(false, "a3 required contract") else aegis.assert.invariant(false, "a3 required contract");
}
