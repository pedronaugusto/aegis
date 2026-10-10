//! Typestate machines against their hand-written tables and nested switches, and the stages against plain moves.
const std = @import("std");
const ab = @import("ab");
const c = @import("state");
const Io = std.Io;

const iterations = 20_000_000;
const names = [_][]const u8{ "next", "next_wide", "next_switch", "next_wide_switch", "step", "plan_commit", "transition" };

/// A cheap deterministic stream of positions, so the predictor sees a mix of legal and illegal pairs.
fn advance(state: u64) u64 {
    return state *% 6364136223846793005 +% 1442695040888963407;
}

noinline fn measure(comptime wrapped: bool, comptime name: []const u8, io: Io, count: usize) error{}!f64 {
    var accumulator: i64 = 0;
    var stream: u64 = 0x5eed;
    var machine: c.Machine(wrapped) = if (wrapped) .init(0) else .{ .payload = 0 };
    var dialing: if (wrapped) c.Dialing else c.Key = undefined;
    var idle: if (wrapped) c.Idle else c.Key = undefined;
    const start = Io.Clock.awake.now(io);
    for (0..count) |_| {
        stream = advance(stream);
        const s: c.State = @fromBackingInt(@as(u8, @truncate(stream >> 33)) % 4); // safe: four states
        const e: c.Event = @fromBackingInt(@as(u8, @truncate(stream >> 41)) % 4); // safe: four events
        if (comptime std.mem.eql(u8, name, "next")) {
            accumulator +%= c.next(wrapped, s, e);
        } else if (comptime std.mem.eql(u8, name, "next_wide")) {
            accumulator +%= c.nextWide(wrapped, @fromBackingInt(@as(u8, @truncate(stream >> 33)) % 8), @fromBackingInt(@as(u8, @truncate(stream >> 41)) % 7)); // safe: eight states and seven events
        } else if (comptime std.mem.eql(u8, name, "next_switch")) {
            accumulator +%= c.nextSwitch(wrapped, s, e);
        } else if (comptime std.mem.eql(u8, name, "next_wide_switch")) {
            accumulator +%= c.nextWideSwitch(wrapped, @fromBackingInt(@as(u8, @truncate(stream >> 33)) % 8), @fromBackingInt(@as(u8, @truncate(stream >> 41)) % 7)); // safe: eight states and seven events
        } else if (comptime std.mem.eql(u8, name, "step")) {
            const result = c.step(wrapped, &machine, e);
            accumulator +%= result;
            if (machine.state == .closed) machine.state = .idle;
        } else if (comptime std.mem.eql(u8, name, "plan_commit")) {
            const result = c.planCommit(wrapped, &machine, e);
            accumulator +%= result;
            if (machine.state == .closed) machine.state = .idle;
        } else {
            const fresh: c.Key = .init(@splat(@truncate(stream)));
            idle = if (wrapped) .init(fresh) else fresh;
            c.transition(wrapped, &idle, &dialing);
            std.mem.doNotOptimizeAway(&dialing);
        }
    }
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}

pub fn main(init: std.process.Init) !void {
    try ab.run(&names, measure, init, iterations);
}
