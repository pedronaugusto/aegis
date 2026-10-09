//! Independent finite-width retirement/clear fixture; no test-only public API.
const std = @import("std");
const pool = @import("pool");
const t = std.testing;
const Tag = struct {};
fn ignore(_: *u32) void {}
pub fn main() !void {
    try removals();
    try clears();
}
fn removals() !void {
    const P = pool.WithGeneration(u32, Tag, u2);
    var slots: [2]P.Slot = undefined;
    var p = try P.initBuffer(&slots, .{ .namespace = 7, .serial = 1 });
    var previous: [6]P.Key = undefined;
    for (0..6) |i| {
        var value: u32 = 31;
        const key = try p.insert(&value);
        previous[i] = key;
        for (previous[0..i]) |old| try t.expect(!p.contains(old));
        var removed: u32 = undefined;
        try p.remove(key, &removed);
    }
    var value: u32 = 11;
    try t.expectError(error.Full, p.insert(&value));
    try t.expectEqual(@as(u32, 11), value);
    p.clear(ignore);
    try t.expectError(error.Full, p.insert(&value));
    try t.expectEqual(@as(usize, 2), p.retired);
}
fn clears() !void {
    const P = pool.WithGeneration(u32, Tag, u2);
    var slots: [1]P.Slot = undefined;
    var p = try P.initBuffer(&slots, .{ .namespace = 7, .serial = 1 });
    for (0..3) |_| {
        var value: u32 = 1;
        const key = try p.insert(&value);
        p.clear(ignore);
        try t.expect(!p.contains(key));
    }
    var value: u32 = 2;
    try t.expectError(error.Full, p.insert(&value));
    try t.expectEqual(@as(usize, 1), p.retired);
}
