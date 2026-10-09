//! Portable pure ownership/bounds profiles, separate from host Io execution.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
fn cleanup(_: *u64) void {}
comptime {
    if (builtin.mode != .debug) {
        std.debug.assert(@sizeOf(a.own.Owned(u64, cleanup)) == @sizeOf(u64));
        std.debug.assert(@alignOf(a.own.Owned(u64, cleanup)) == @alignOf(u64));
        std.debug.assert(@sizeOf(a.own.MustUse(u64, "read")) == @sizeOf(u64));
        std.debug.assert(@sizeOf(a.InitContext) == 0);
        std.debug.assert(@sizeOf(a.Order(&.{.{ .name = "root" }}).Context) == 0);
    }
    if (builtin.mode == .fast or builtin.mode == .small) std.debug.assert(@sizeOf(a.Confined(u64)) == @sizeOf(u64));
}
export fn pure(seed: u64) u64 {
    var array: a.bounded.Array(u64, 3) = .init;
    var queue: a.bounded.Queue(u64, 3) = .init;
    var input = seed;
    array.append(&input) catch return 0;
    queue.push(&input) catch return 0;
    var output: u64 = undefined;
    queue.pop(&output) catch return 0;
    var budget = a.bounded.Budget(u64).init(seed);
    var reservation = budget.reserve(seed) catch return 0;
    reservation.release();
    var owner = a.own.Owned(u64, cleanup).init(output);
    owner.take(&output);
    var outcome = a.own.MustUse(u64, "read").init(output);
    outcome.take(&output);
    outcome.deinit();
    var confined = a.Confined(u64).init(@fromBackingInt(@intCast(1)), output);
    return confined.value(@fromBackingInt(@intCast(1))).*;
}
