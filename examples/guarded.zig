//! Request counters four workers update: the data beside its spin lock, reached only through
//! a guard, for sections that never block.
const std = @import("std");
const aegis = @import("aegis");

const Stats = struct { requests: u64 = 0, bytes: u64 = 0 };

fn serve(stats: *aegis.Guarded(Stats), rounds: usize) void {
    for (0..rounds) |_| {
        var held = stats.acquire();
        defer held.deinit();
        // Both fields change under one hold, so no reader sees one without the other.
        held.value().requests += 1;
        held.value().bytes += 512;
    }
}

pub fn main(init: std.process.Init) !void {
    var stats = aegis.Guarded(Stats).init(.{});
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    for (0..4) |_| try group.concurrent(init.io, serve, .{ &stats, 1000 });
    try group.await(init.io);

    // `tryAcquire` never waits: null while someone holds the lock.
    {
        var held = stats.tryAcquire() orelse unreachable; // unreachable: every worker has finished
        defer held.deinit();
        aegis.assert.post(stats.tryAcquire() == null, "a held lock is not taken twice");
    }

    // The last user hands the data over with no lock and no Io.
    const totals = stats.teardown();
    aegis.assert.post(totals.requests == 4000 and totals.bytes == 4000 * 512, "every update counted, none torn");
}
