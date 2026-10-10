//! Portable typestate profile for 32-bit, wasm and freestanding targets.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
const Link = a.state.Machine(enum(u8) { idle, open, closed }, enum(u8) { dial, close }, .{
    .initial = .idle,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .idle, .on = .dial, .to = .open },
        .{ .from = .open, .on = .close, .to = .closed },
    },
});
comptime {
    if (builtin.optimize != .debug) {
        std.debug.assert(@sizeOf(Link.At(.idle, u32)) == @sizeOf(u32));
        std.debug.assert(@alignOf(Link.At(.idle, u32)) == @alignOf(u32));
        std.debug.assert(@sizeOf(Link.At(.closed, void)) == 0);
    }
    std.debug.assert(@sizeOf(Link.Runtime(void)) == 1);
}
export fn pure(seed: u32, event: u8) u32 {
    var idle = Link.At(.idle, u32).init(seed);
    var open: Link.At(.open, u32) = undefined;
    idle.transition(.dial, &open);
    var link = Link.Runtime(u32).init(open.get().*);
    _ = link.step(@fromBackingInt(event)) catch return 0;
    return link.payload +% @backingInt(link.current());
}
