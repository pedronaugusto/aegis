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
    std.debug.assert(@sizeOf(Link.Carrying(Held)) == @sizeOf(Held));
    std.debug.assert(@alignOf(Link.Carrying(Held)) == @alignOf(Held));
}
/// What each state holds, for the carrying machine: the state is the union's tag.
const Held = union(Link.State) { idle: u32, open: u64, closed };
fn dropped(_: void, _: *Held) void {}
export fn pure(seed: u32, event: u8) u32 {
    var idle = Link.At(.idle, u32).init(seed);
    var open: Link.At(.open, u32) = undefined;
    idle.transition(.dial, &open);
    var link = Link.Runtime(u32).init(open.get().*);
    _ = link.step(@fromBackingInt(event)) catch return 0;
    return link.payload +% @backingInt(link.current());
}
export fn carried(seed: u32, event: u8) u64 {
    var link = Link.Carrying(Held).init(seed);
    _ = link.step(@fromBackingInt(event), .{ .open = seed }, {}, dropped) catch return 0;
    return (link.atConst(.open) orelse return 1).*;
}
