//! A mailbox one task fills and another waits on: a condition bound to its owner's lock, the
//! guard held again on every return, waiters bounded.
const std = @import("std");
const aegis = @import("aegis");

const Mailbox = struct {
    letter: aegis.BlockingGuarded(?u32) = .init(null),
    arrived: aegis.Condition = .init(),
};

fn deliver(io: std.Io, mailbox: *Mailbox, value: u32) std.Io.Cancelable!void {
    var held = try mailbox.letter.acquire(io);
    defer held.deinit(io);
    held.value().* = value;
    mailbox.arrived.signal(io);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var mailbox: Mailbox = .{};
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, deliver, .{ io, &mailbox, 42 });
    {
        var held = try mailbox.letter.acquire(io);
        defer held.deinit(io);
        // A predicate loop: a wake proves nothing, the letter does. Each wait returns with the
        // guard held again, whatever ended it.
        while (held.value().* == null) try mailbox.arrived.wait(io, &held, .none);
        aegis.assert.post(held.value().* == 42, "the letter arrived under the lock");
    }
    try group.await(io);
}
