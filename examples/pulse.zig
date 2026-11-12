//! A producer that says "more arrived" every time it adds, and a consumer that waits past the
//! generation it last saw: no reset to race, and no bump lost between a look and a wait.
const std = @import("std");
const aegis = @import("aegis");

const Items = aegis.units.Count(struct {}, u32);
const total: Items = .fromRaw(64);

fn consume(io: std.Io, arrived: *const aegis.Pulse, count: *const aegis.Atomic(Items), seen_all: *aegis.Atomic(Items)) std.Io.Cancelable!void {
    var seen = arrived.current();
    while (count.load(.acquire).compare(total) == .lt) seen = try arrived.waitPast(io, seen);
    seen_all.store(count.load(.acquire), .release);
}

pub fn main(init: std.process.Init) !void {
    var arrived: aegis.Pulse = .init();
    var count: aegis.Atomic(Items) = .init(.fromRaw(0));
    var seen_all: aegis.Atomic(Items) = .init(.fromRaw(0));
    var consumer = try init.io.concurrent(consume, .{ init.io, &arrived, &count, &seen_all });
    for (0..total.raw()) |_| {
        _ = count.fetchAddWrapping(.fromRaw(1), .release);
        arrived.bump(init.io);
    }
    try consumer.await(init.io);
    aegis.assert.invariant(seen_all.load(.acquire).eql(total), "the consumer saw every item");
}
