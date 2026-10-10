//! Deliberate typestate violations in isolated child processes, never live station turns.
const std = @import("std");
const a = @import("aegis");
const Link = a.state.Machine(enum { idle, open, closed }, enum { dial, drop, close }, .{
    .initial = .idle,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .idle, .on = .dial, .to = .open },
        .{ .from = .idle, .on = .drop, .to = .idle },
        .{ .from = .open, .on = .close, .to = .closed },
    },
});
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const name = args[1];
    if (std.mem.eql(u8, name, "stage-reuse")) {
        var idle = Link.At(.idle, u64).init(1);
        var open: Link.At(.open, u64) = undefined;
        idle.transition(.dial, &open);
        std.mem.doNotOptimizeAway(idle.get().*);
    } else if (std.mem.eql(u8, name, "stage-alias")) {
        var idle = Link.At(.idle, u64).init(1);
        const same: *Link.At(.idle, u64) = &idle;
        same.transition(.drop, same);
    } else if (std.mem.eql(u8, name, "commit-forged")) {
        var link = Link.Runtime(u64).init(1);
        try link.commit(.{ .from = .idle, .on = .close, .to = .closed });
    } else if (std.mem.eql(u8, name, "take-twice")) {
        var idle = Link.At(.idle, u64).init(1);
        var open: Link.At(.open, u64) = undefined;
        idle.transition(.dial, &open);
        var closed: Link.At(.closed, u64) = undefined;
        open.transition(.close, &closed);
        var out: u64 = undefined;
        closed.take(&out);
        closed.take(&out);
    } else return error.UnknownCase;
}
