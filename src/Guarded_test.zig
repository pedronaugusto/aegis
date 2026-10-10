const std = @import("std");
const Guarded = @import("root.zig").Guarded;

fn fail(owner: *Guarded(u64)) error{Injected}!void {
    var held = owner.acquire();
    defer held.deinit();
    held.value().* += 1;
    return error.Injected;
}

test "Guarded error cleanup independent owners early release and reacquisition" {
    var first = Guarded(u64).init(0);
    var second = Guarded(u64).init(7);
    try std.testing.expectError(error.Injected, fail(&first));
    var a = first.acquire();
    var b = second.acquire();
    defer b.deinit();
    try std.testing.expectEqual(@as(u64, 1), a.value().*);
    try std.testing.expectEqual(@as(u64, 7), b.value().*);
    a.deinit();
    a = first.acquire();
    defer a.deinit();
    a.value().* += 1;
}

const Shared = struct { count: usize = 0, checksum: usize = 0 };
fn worker(owner: *Guarded(Shared), rounds: usize) void {
    for (0..rounds) |_| {
        var held = owner.acquire();
        defer held.deinit();
        const data = held.value();
        std.debug.assert(data.checksum == data.count *% 17);
        data.count += 1;
        data.checksum = data.count *% 17;
    }
}

test "Guarded native contention mutual exclusion and publication" {
    for ([_]usize{ 2, 8 }) |threads| {
        var owner = Guarded(Shared).init(.{});
        var group: std.Io.Group = .init;
        defer group.cancel(std.testing.io);
        for (0..threads) |_| try group.concurrent(std.testing.io, worker, .{ &owner, 2000 });
        try group.await(std.testing.io);
        var held = owner.acquire();
        defer held.deinit();
        try std.testing.expectEqual(threads * 2000, held.value().count);
        try std.testing.expectEqual(threads * 2000 * 17, held.value().checksum);
    }
}

fn schedulingWorker(owner: *Guarded(Shared), rounds: usize) void {
    for (0..rounds) |_| {
        var held = owner.acquireScheduling();
        defer held.deinit();
        held.value().count += 1;
        held.value().checksum += 17;
    }
}

test "Guarded scheduling acquire keeps mutual exclusion and sees a held lock" {
    var owner = Guarded(Shared).init(.{});
    var first = owner.acquireScheduling();
    try std.testing.expect(owner.isHeld());
    try std.testing.expect(owner.tryAcquire() == null);
    first.deinit();
    try std.testing.expect(!owner.isHeld());
    var group: std.Io.Group = .init;
    defer group.cancel(std.testing.io);
    for (0..4) |_| try group.concurrent(std.testing.io, schedulingWorker, .{ &owner, 2000 });
    try group.await(std.testing.io);
    var held = owner.acquire();
    defer held.deinit();
    try std.testing.expectEqual(@as(usize, 4 * 2000), held.value().count);
    try std.testing.expectEqual(@as(usize, 4 * 2000 * 17), held.value().checksum);
}
