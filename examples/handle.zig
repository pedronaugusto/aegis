//! Timers kept in a pool and named by keys: a removed timer's key stops working, even after
//! its slot is reused, in every build mode.
const aegis = @import("aegis");

const handle = aegis.handle;
const Timer = struct { deadline_ms: u64 };
const Timers = handle.Pool(Timer, Timer);

fn drop(_: *Timer) void {}

pub fn main() !void {
    // Instances keep two pools' keys apart; the namespace is the caller's to keep unique.
    var domain = handle.Domain.init(0x7469_6d65);
    var slots: [2]Timers.Slot = undefined;
    var timers = try Timers.initBuffer(&slots, try domain.issue());
    defer timers.deinit(drop);

    var timer: Timer = .{ .deadline_ms = 250 };
    const first = try timers.insert(&timer);
    aegis.assert.invariant((try timers.get(first)).deadline_ms == 250, "a live key reaches its timer");

    var removed: Timer = undefined;
    try timers.remove(first, &removed);
    timer = .{ .deadline_ms = 900 };
    const second = try timers.insert(&timer); // the same slot, a new generation
    if (timers.get(first)) |_| unreachable else |err| aegis.assert.invariant(err == error.InvalidKey, "a stale key is refused, the slot's new timer untouched");
    aegis.assert.invariant((try timers.get(second)).deadline_ms == 900, "the new key works");

    // A position in a slice, branded and checked against the slice at every access.
    const Position = handle.Index(Timer, u16);
    const deadlines = [_]u64{ 10, 20, 30 };
    const at = try Position.from(2, deadlines.len);
    aegis.assert.invariant((try at.get(deadlines[0..])).* == 30, "in bounds");
    if (at.get(deadlines[0..2])) |_| unreachable else |err| aegis.assert.invariant(err == error.OutOfBounds, "checked against the slice it reads");
}
