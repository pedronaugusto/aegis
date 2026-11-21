//! A shutdown that one side decides and every worker waits for: the reason travels with the
//! signal, and a second decision is answered false rather than overwriting the first.
const std = @import("std");
const aegis = @import("aegis");

const Stop = enum(u8) { drained, canceled };

fn worker(io: std.Io, stop: *const aegis.Signal(Stop), seen: *aegis.Atomic(Stop)) std.Io.Cancelable!void {
    const reason = try stop.wait(io);
    seen.store(reason.*, .release);
}

pub fn main(init: std.process.Init) !void {
    var stop = aegis.Signal(Stop).init();
    var seen: aegis.Atomic(Stop) = .init(.canceled);
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    for (0..4) |_| try group.concurrent(init.io, worker, .{ init.io, &stop, &seen });
    aegis.assert.invariant(stop.set(init.io, .drained), "the first decision sets the signal");
    // Whoever comes second learns it lost; the reason stays the first one.
    aegis.assert.invariant(!stop.set(init.io, .canceled), "a signal is set once");
    try group.await(init.io);
    aegis.assert.invariant(seen.load(.acquire) == .drained, "every worker saw the first reason");
}
