//! A lookup table computed on first use from nothing but its inputs: `Once` for a leaf
//! initializer, with no task context and only the initializer's own errors.
const std = @import("std");
const aegis = @import("aegis");

const Squares = struct { values: [16]u32 };

fn compute(calls: *std.atomic.Value(u32), table: *Squares) void {
    _ = calls.fetchAdd(1, .monotonic);
    for (&table.values, 0..) |*value, i| value.* = @intCast(i * i);
}

fn worker(io: std.Io, squares: *aegis.Lazy(Squares), calls: *std.atomic.Value(u32), sum: *std.atomic.Value(u64)) void {
    // An infallible initializer: no error, and a const view, as `Squares` has no lock of its own.
    const table: *const Squares = squares.getOrInit(io, calls, compute);
    _ = sum.fetchAdd(table.values[15], .monotonic);
}

pub fn main(init: std.process.Init) !void {
    var squares = aegis.Lazy(Squares).init();
    var calls: std.atomic.Value(u32) = .init(0);
    var sum: std.atomic.Value(u64) = .init(0);
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    for (0..4) |_| try group.concurrent(init.io, worker, .{ init.io, &squares, &calls, &sum });
    try group.await(init.io);
    aegis.assert.invariant(calls.load(.monotonic) == 1, "computed exactly once, whoever came first");
    aegis.assert.invariant(sum.load(.monotonic) == 4 * 225, "every caller saw the finished table");
}
