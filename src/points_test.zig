//! Fault points in a test build: inert with no driver, every verb handed to an installed driver
//! with the point's name, one driver at a time.
const std = @import("std");
const t = std.testing;
const points = @import("points.zig");

const Point = enum { append_fails, short_read, slow_path, recovered };

/// A driver that answers from fixed values and records what it was asked.
const Recorder = struct {
    fail: bool = false,
    short: usize = 1,
    asked: [8]points.Point = undefined,
    count: usize = 0,

    const vtable: points.Driver.VTable = .{ .fault = fault, .shorten = shorten, .yield = yield, .reached = reached };

    fn of(context: *anyopaque) *Recorder {
        return @ptrCast(@alignCast(context)); // safe: every driver of this vtable is made over a Recorder
    }
    fn keep(r: *Recorder, point: points.Point) void {
        r.asked[r.count] = point;
        r.count += 1;
    }
    fn fault(context: *anyopaque, point: points.Point) bool {
        const r = of(context);
        r.keep(point);
        return r.fail;
    }
    fn shorten(context: *anyopaque, point: points.Point, n: usize) usize {
        const r = of(context);
        r.keep(point);
        return @min(r.short, n);
    }
    fn yield(context: *anyopaque, point: points.Point) void {
        of(context).keep(point);
    }
    fn reached(context: *anyopaque, point: points.Point) void {
        of(context).keep(point);
    }
};

test "points: with no driver every verb gives its inert answer" {
    try t.expect(!points.fault(Point.append_fails));
    try t.expectEqual(@as(usize, 4096), points.shorten(Point.short_read, 4096));
    try t.expectEqual(@as(usize, 0), points.shorten(Point.short_read, 0));
    points.yield(Point.slow_path);
    points.reached(Point.recovered);
}

test "points: an installed driver decides every verb and is handed the point's name" {
    var r: Recorder = .{ .fail = true, .short = 7 };
    const driver: points.Driver = .{ .context = &r, .vtable = &Recorder.vtable };
    try points.install(&driver);
    defer points.uninstall(&driver);
    try t.expect(points.fault(Point.append_fails));
    try t.expectEqual(@as(usize, 7), points.shorten(Point.short_read, 4096));
    // A length of 0 is not shortened, and the driver is not asked.
    try t.expectEqual(@as(usize, 0), points.shorten(Point.short_read, 0));
    points.yield(Point.slow_path);
    points.reached(Point.recovered);
    try t.expectEqual(@as(usize, 4), r.count);
    const names = [_][]const u8{ "append_fails", "short_read", "slow_path", "recovered" };
    for (names, r.asked[0..4]) |name, asked| {
        try t.expectEqualStrings(name, asked.name);
        try t.expectEqualStrings(@typeName(Point), asked.set);
    }
}

test "points: a second driver is refused while one is installed, and taken once it is removed" {
    var first: Recorder = .{};
    var second: Recorder = .{ .fail = true };
    const one: points.Driver = .{ .context = &first, .vtable = &Recorder.vtable };
    const two: points.Driver = .{ .context = &second, .vtable = &Recorder.vtable };
    try points.install(&one);
    try t.expectError(error.AlreadyInstalled, points.install(&two));
    try t.expect(!points.fault(Point.append_fails));
    points.uninstall(&one);
    try points.install(&two);
    defer points.uninstall(&two);
    try t.expect(points.fault(Point.append_fails));
    // Only the first was asked while it was installed.
    try t.expectEqual(@as(usize, 1), first.count);
}

test "points: list names every point of a set, in declaration order" {
    const all = points.list(Point);
    try t.expectEqual(@as(usize, 4), all.len);
    try t.expectEqualStrings("append_fails", all[0].name);
    try t.expectEqualStrings("recovered", all[3].name);
    var buffer: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try w.print("{f}", .{all[1]});
    try t.expectEqualStrings(@typeName(Point) ++ ".short_read", w.buffered());
}
