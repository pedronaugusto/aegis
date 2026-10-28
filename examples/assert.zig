//! A buffer pool's invariants written as code: checked and stopping in every build, where
//! Zig's `unreachable` would be undefined behavior in ReleaseFast.
const std = @import("std");
const aegis = @import("aegis");

const assert = aegis.assert;

const Pool = struct {
    free: u32,
    total: u32,

    fn take(pool: *Pool) error{Exhausted}!u32 {
        // Running out is an event a caller handles: an error, never an assertion.
        if (pool.free == 0) return error.Exhausted;
        assert.invariant(pool.free <= pool.total, "free buffers never exceed the pool");
        pool.free -= 1;
        assert.invariant(pool.free < pool.total, "a taken buffer is not free");
        return pool.total - pool.free - 1;
    }

    fn kind(slot: u32) []const u8 {
        return switch (slot % 2) {
            0 => "even",
            1 => "odd",
            // The checked form of `unreachable`: it stops in every build mode.
            else => assert.never("a remainder of 2 is 0 or 1"),
        };
    }

    fn consistent(pool: *const Pool) bool {
        return pool.free <= pool.total;
    }
};

pub fn main() !void {
    var pool: Pool = .{ .free = 2, .total = 2 };
    const slot = try pool.take();
    assert.invariant(Pool.consistent(&pool), "the pool's counts agree");
    aegis.assert.invariant(std.mem.eql(u8, Pool.kind(slot), "even"), "the first slot is 0");
    _ = try pool.take();
    if (pool.take()) |_| unreachable else |err| assert.invariant(err == error.Exhausted, "an empty pool says so");

    // Diagnostics a hot path can afford only in Debug: the predicate is not even called in
    // the release modes.
    assert.debugCheck(Pool.consistent, &pool);
    assert.debug(pool.free == 0, "drained");
}
