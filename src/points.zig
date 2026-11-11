//! Fault points: places a package marks in its own code where a test may make it misbehave, as
//! FoundationDB's BUGGIFY does, without the package importing any test library. A point is a tag
//! of an enum the package declares beside the code (`pub const Point = enum { append_fails }`):
//! the enum is the list of its points, and a point's name is the enum's type name and the tag.
//!
//! - `fault(point)`: whether to misbehave here. The package writes what that means, so the error
//!   it returns is one of its function's own: `if (points.fault(Point.append_fails)) return
//!   error.InputOutput;`.
//! - `shorten(point, n)`: a length, a read size or a timeout in `[1, n]` (0 stays 0).
//! - `yield(point)`: let another task run here.
//! - `reached(point)`: mark that a state was reached; it decides nothing.
//!
//! Outside a test build (`builtin.is_test`) every verb is its inert answer, known as it
//! compiles: `false`, `n`, nothing. No branch, load or symbol is left (ci/points_parity.zig holds
//! that in ReleaseFast and ReleaseSafe). In a test build each verb costs one atomic load of the
//! driver slot and one compare against null while no driver is installed. A driver (shakedown's,
//! around each case) decides each point it is asked, and is the only global: one slot, installed
//! by one runner at a time.
const std = @import("std");
const builtin = @import("builtin");

/// A point as a driver is handed it: its enum's type name and its tag.
pub const Point = struct {
    set: []const u8,
    name: []const u8,

    pub fn format(p: Point, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s}.{s}", .{ p.set, p.name });
    }
};

/// What decides the points while it is installed.
pub const Driver = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        fault: *const fn (context: *anyopaque, point: Point) bool,
        /// At least 1 and at most `n`, for an `n` of at least 1.
        shorten: *const fn (context: *anyopaque, point: Point, n: usize) usize,
        yield: *const fn (context: *anyopaque, point: Point) void,
        reached: *const fn (context: *anyopaque, point: Point) void,
    };
};

/// The one driver slot; ci/codegen.zig looks for its name in builds outside a test.
var points_driver_slot: std.atomic.Value(?*const Driver) = .init(null);

/// Installs `driver` until `uninstall`. A driver already installed is a second runner at once,
/// refused.
pub fn install(driver: *const Driver) error{AlreadyInstalled}!void {
    if (points_driver_slot.cmpxchgStrong(null, driver, .acq_rel, .acquire) != null) return error.AlreadyInstalled;
}

/// Removes `driver`, which is the one installed.
pub fn uninstall(driver: *const Driver) void {
    const was = points_driver_slot.swap(null, .acq_rel);
    std.debug.assert(was == driver);
}

/// Every point of the enum `Set`, as drivers are handed them: the list a test names to count.
pub fn list(comptime Set: type) []const Point {
    return comptime blk: {
        const tags = std.meta.tags(Set);
        var points: [tags.len]Point = undefined;
        for (tags, &points) |tag, *p| p.* = .{ .set = @typeName(Set), .name = @tagName(tag) };
        const all = points;
        break :blk &all;
    };
}

/// Whether to misbehave at `point`; false unless a test's driver says so.
pub inline fn fault(point: anytype) bool {
    if (comptime !builtin.is_test) return false;
    const driver = points_driver_slot.load(.acquire) orelse return false;
    return driver.vtable.fault(driver.context, of(point));
}

/// `n`, or less where a test's driver shortens it: in `[1, n]`, and 0 for an `n` of 0.
pub inline fn shorten(point: anytype, n: usize) usize {
    if (comptime !builtin.is_test) return n;
    if (n == 0) return 0;
    const driver = points_driver_slot.load(.acquire) orelse return n;
    const short = driver.vtable.shorten(driver.context, of(point), n);
    std.debug.assert(short >= 1 and short <= n);
    return short;
}

/// Lets another task run at `point` where a test's driver runs tasks.
pub inline fn yield(point: anytype) void {
    if (comptime !builtin.is_test) return;
    const driver = points_driver_slot.load(.acquire) orelse return;
    driver.vtable.yield(driver.context, of(point));
}

/// Marks that `point` was reached, for a test's driver to count; it decides nothing.
pub inline fn reached(point: anytype) void {
    if (comptime !builtin.is_test) return;
    const driver = points_driver_slot.load(.acquire) orelse return;
    driver.vtable.reached(driver.context, of(point));
}

fn of(point: anytype) Point {
    const Set = @TypeOf(point);
    if (@typeInfo(Set) != .@"enum") @compileError("a point is a tag of the package's own point enum, not a " ++ @typeName(Set));
    return .{ .set = @typeName(Set), .name = @tagName(point) };
}
