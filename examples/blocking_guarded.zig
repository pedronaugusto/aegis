//! A job list workers drain through a `std.Io.Mutex`: a section that may block or wait, with
//! the Io passed at each call and never stored.
const std = @import("std");
const aegis = @import("aegis");

const Jobs = struct { pending: u32, done: u32 = 0 };

fn work(io: std.Io, jobs: *aegis.BlockingGuarded(Jobs)) std.Io.Cancelable!void {
    while (true) {
        var held = try jobs.acquire(io); // a cancellation point: canceled, it grants nothing
        defer held.deinit(io);
        const state = held.value();
        if (state.pending == 0) return;
        state.pending -= 1;
        state.done += 1;
    }
}

pub fn main(init: std.process.Init) !void {
    var jobs = aegis.BlockingGuarded(Jobs).init(.{ .pending = 300 });
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    for (0..3) |_| try group.concurrent(init.io, work, .{ init.io, &jobs });
    try group.await(init.io);

    // A cleanup path that must run takes the lock past a cancellation request.
    {
        var held = jobs.acquireUncancelable(init.io);
        defer held.deinit(init.io);
        aegis.assert.post(jobs.isHeld(), "the lock reads held while a guard is live");
    }
    const finished = jobs.teardown();
    aegis.assert.post(finished.done == 300 and finished.pending == 0, "each job ran exactly once");
}
