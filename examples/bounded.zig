//! A connection's outgoing queue and its byte budget: fixed capacity, explicit failure when
//! full, and admission that can never pass its maximum.
const aegis = @import("aegis");

const bounded = aegis.bounded;
const Frame = struct { id: u32, len: u32 };

fn forget(_: *u32) void {}

pub fn main() !void {
    var outgoing: bounded.Queue(Frame, 2) = .init;
    var frame: Frame = .{ .id = 1, .len = 100 };
    try outgoing.push(&frame);
    frame = .{ .id = 2, .len = 200 };
    try outgoing.push(&frame);
    // Full is an answer, and the frame stays with the caller.
    frame = .{ .id = 3, .len = 300 };
    if (outgoing.push(&frame)) |_| unreachable else |err| aegis.assert.invariant(err == error.Full, "a full queue refuses");
    aegis.assert.post(outgoing.isFull() and frame.id == 3, "nothing was overwritten");
    var sent: Frame = undefined;
    try outgoing.pop(&sent);
    aegis.assert.post(sent.id == 1, "first in, first out");

    // Bytes in flight: an allocation is charged before it is made, released if it fails,
    // consumed once it succeeds.
    var in_flight = bounded.Budget(u32).init(1024);
    var charge = try in_flight.reserve(600);
    charge.consume();
    // Ordinary work leaves 100 bytes for the control path (a cancel must still get through).
    if (in_flight.reserveKeeping(400, 100)) |_| unreachable else |err| aegis.assert.invariant(err == error.LimitExceeded, "ordinary work cannot take the kept room");
    var cancel = try in_flight.reserve(100);
    defer cancel.release();
    aegis.assert.post(in_flight.remaining() == 324, "the budget never holds more than its maximum");

    // A growable array with a hard ceiling, its storage the caller's.
    var storage: [4]u32 = undefined;
    var ids = bounded.Buffer(u32).initBuffer(&storage);
    defer ids.deinit(forget);
    for (0..4) |i| {
        var id: u32 = @intCast(i);
        try ids.append(&id);
    }
    aegis.assert.post(ids.isFull() and ids.items()[3] == 3, "four in four");
}
