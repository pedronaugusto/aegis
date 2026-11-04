//! Timers kept in a pool and named by keys: a removed timer's key stops working, even after
//! its slot is reused, in every build mode. The pool grows on a region of its own, so a timer
//! never moves while it lives.
const aegis = @import("aegis");

const handle = aegis.handle;
const Timer = struct { deadline_ms: u64 };
const Timers = handle.SlotPool(Timer, Timer, .{ .generation = u64 });

fn drop(_: *Timer) void {}

const Node = struct { value: u32, next: handle.OptionalIndex(Node, u32) };
const Nodes = handle.SlotPool(Node, Node, .{});

pub fn main() !void {
    // Instances keep two pools' keys apart; the namespace is the caller's to keep unique.
    var domain = handle.Domain.init(0x7469_6d65);
    var timers = try Timers.init(try aegis.Region.reserve(.init(1 << 20)), try domain.issue());
    defer timers.deinit(drop);

    var timer: Timer = .{ .deadline_ms = 250 };
    const first = try timers.insert(&timer);
    const live = try timers.get(first);
    aegis.assert.invariant(live.deadline_ms == 250, "a live key reaches its timer");

    var removed: Timer = undefined;
    try timers.remove(first, &removed);
    timer = .{ .deadline_ms = 900 };
    const second = try timers.insert(&timer); // the same slot, a new generation
    if (timers.get(first)) |_| unreachable else |err| aegis.assert.invariant(err == error.InvalidKey, "a stale key is refused, the slot's new timer untouched");
    aegis.assert.invariant((try timers.get(second)).deadline_ms == 900, "the new key works");

    // A dense pool of bare four-byte indexes: a node links to another by index, and an optional
    // link costs no more than a link.
    var nodes = Nodes.init(try aegis.Region.reserve(.init(1 << 20)));
    defer nodes.deinit();
    const tail = try nodes.alloc(.{ .value = 2, .next = .none });
    const head = try nodes.create(); // built in place, knowing its own index
    head.value.* = .{ .value = 1, .next = .some(tail) };
    aegis.assert.invariant(nodes.get(head.handle).value == 1, "the head");
    aegis.assert.invariant(@sizeOf(Nodes.Handle) == 4 and @sizeOf(Nodes.OptionalHandle) == 4, "four bytes either way");

    // A position in a slice, branded and checked against the slice at every access.
    const Position = handle.Index(Timer, u16);
    const deadlines = [_]u64{ 10, 20, 30 };
    const at = try Position.from(2, deadlines.len);
    aegis.assert.invariant((try at.get(deadlines[0..])).* == 30, "in bounds");
    if (at.get(deadlines[0..2])) |_| unreachable else |err| aegis.assert.invariant(err == error.OutOfBounds, "checked against the slice it reads");
}
