const std = @import("std");
const shake = @import("shakedown");
const b = @import("../bounded.zig");
const own = @import("../own.zig");
const t = std.testing;
fn noop(_: *u32) void {}

test "A7 array prefix boundary and destination conservation" {
    var a: b.Array(u32, 2) = .init;
    var v: u32 = 7;
    try a.append(&v);
    v = 8;
    try a.append(&v);
    v = 9;
    try t.expectError(error.Full, a.append(&v));
    try t.expectEqual(@as(u32, 9), v);
    try t.expectError(error.OutOfBounds, a.at(2));
    try a.pop(&v);
    try t.expectEqual(@as(u32, 8), v);
    a.clear(noop);
    try t.expectError(error.Empty, a.pop(&v));
    try t.expectEqual(@as(u32, 8), v);
    var zero: b.Array(u32, 0) = .init;
    try t.expectError(error.Full, zero.append(&v));
}
fn fifo(_: void, c: *shake.Case) anyerror!void {
    var q: b.Queue(u32, 3) = .init;
    var oracle: std.ArrayList(u32) = .empty;
    defer oracle.deinit(t.allocator);
    for (0..256) |_| {
        var value = shake.gen.int(c.source, u32);
        const action = shake.gen.intRange(c.source, u8, 0, 3);
        if (action == 0) {
            if (oracle.items.len == 3) try t.expectError(error.Full, q.push(&value)) else {
                try q.push(&value);
                try oracle.append(t.allocator, value);
            }
        } else if (action == 1) {
            if (oracle.items.len == 0) try t.expectError(error.Empty, q.pop(&value)) else {
                const expected = oracle.orderedRemove(0);
                try q.pop(&value);
                try t.expectEqual(expected, value);
            }
        } else if (action == 2) {
            var evicted: u32 = undefined;
            const full = oracle.items.len == 3;
            const expected = if (full) oracle.orderedRemove(0) else 0;
            try t.expectEqual(full, q.overwrite(&value, &evicted));
            if (full) try t.expectEqual(expected, evicted);
            try oracle.append(t.allocator, value);
        } else {
            if (oracle.items.len == 0) try t.expectError(error.Empty, q.peek()) else try t.expectEqual(oracle.items[0], (try q.peek()).*);
        }
        try t.expectEqual(oracle.items.len, q.len());
    }
}
test "A7 queue arbitrary capacity wrap and overwrite independent FIFO oracle" {
    try shake.check(t.allocator, {}, fifo, .{ .cases = 256, .seed = 0xa7 });
    var one: b.Ring(u32, 1) = .init;
    var x: u32 = 1;
    try one.push(&x);
    x = 2;
    var evicted: u32 = undefined;
    try t.expect(one.overwrite(&x, &evicted));
    try t.expectEqual(@as(u32, 1), evicted);
    try one.pop(&x);
    try t.expectEqual(@as(u32, 2), x);
}
test "A7 reservations transfer reap rollback and permanent consumption" {
    var bytes = b.Budget(u8).init(255);
    var jobs = b.Budget(u8).init(0);
    var charge = try bytes.reserve(254);
    if (jobs.reserve(1)) |_| return error.ExpectedLimit else |err| {
        try t.expectEqual(error.LimitExceeded, err);
        charge.release();
    }
    try t.expectEqual(@as(u8, 255), bytes.remaining());
    charge = try bytes.reserve(254);
    try t.expectError(error.LimitExceeded, bytes.reserve(2));
    var transferred: b.Budget(u8).Reservation = undefined;
    charge.moveInto(&transferred);
    try bytes.consume(1);
    transferred.release();
    try t.expectEqual(@as(u8, 254), bytes.remaining());
    try t.expectError(error.LimitExceeded, b.Limit(u8).init(0).check(1));
    try b.Limit(u8).init(0).check(0);
}
const Resource = struct {
    gpa: std.mem.Allocator,
    bytes: []u8,
    cleaned: *usize,
    fn deinit(self: *Resource) void {
        self.gpa.free(self.bytes);
        self.cleaned.* += 1;
        self.* = undefined;
    }
};
fn construction(gpa: std.mem.Allocator) !void {
    var cleaned: usize = 0;
    var resources = try b.Buffer(Resource).initAllocated(gpa, 1, 8);
    defer resources.deinit(Resource.deinit);
    var resource: Resource = .{ .gpa = gpa, .bytes = try gpa.alloc(u8, 16), .cleaned = &cleaned };
    resources.append(&resource) catch |err| {
        resource.deinit();
        return err;
    };
    const old_ptr = resources.items().ptr;
    resources.reserve(8) catch |err| {
        try t.expect(resources.items().ptr == old_ptr);
        try t.expectEqual(@as(usize, 1), resources.len());
        return err;
    };
    try t.expectEqual(@as(usize, 0), cleaned);
    resources.clear(Resource.deinit);
    try t.expectEqual(@as(usize, 1), cleaned);
}
test "A7 allocated capacity OOM preserves owners on NoResize" {
    var no_resize = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(no_resize.allocator(), construction, .{});
    var storage: [2]u32 = undefined;
    var buffer = b.Buffer(u32).initBuffer(&storage);
    try t.expectError(error.CapacityExceeded, buffer.reserve(3));
    var value: u32 = 1;
    try buffer.append(&value);
    try buffer.pop(&value);
    try t.expectEqual(@as(u32, 1), value);
}
fn owningFailure(gpa: std.mem.Allocator) !void {
    var cleaned: usize = 0;
    const O = own.Owned(Resource, Resource.deinit);
    var owner = O.init(.{ .gpa = gpa, .bytes = try gpa.alloc(u8, 32), .cleaned = &cleaned });
    errdefer owner.deinit();
    const auxiliary = try gpa.alloc(u8, 16);
    defer gpa.free(auxiliary);
    owner.borrowMut().bytes[0] = 42;
    var moved: O = undefined;
    owner.moveInto(&moved);
    try t.expectEqual(@as(u8, 42), moved.borrow().bytes[0]);
    var raw: Resource = undefined;
    moved.take(&raw);
    raw.deinit();
    try t.expectEqual(@as(usize, 1), cleaned);
}
test "A7 Owned allocation failure transfer and exactly one static cleanup" {
    var no_resize = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(no_resize.allocator(), owningFailure, .{});
}
test "A7 owning ring eviction cleanup happens outside the container" {
    var cleaned: usize = 0;
    var q: b.Queue(Resource, 1) = .init;
    defer q.deinit(Resource.deinit);
    var first: Resource = .{ .gpa = t.allocator, .bytes = try t.allocator.alloc(u8, 1), .cleaned = &cleaned };
    try q.push(&first);
    var second: Resource = .{ .gpa = t.allocator, .bytes = try t.allocator.alloc(u8, 1), .cleaned = &cleaned };
    var evicted: Resource = undefined;
    try t.expect(q.overwrite(&second, &evicted));
    try t.expectEqual(@as(usize, 0), cleaned);
    evicted.deinit();
    q.clear(Resource.deinit);
    try t.expectEqual(@as(usize, 2), cleaned);
}
test "A7 MustUse take and documented acknowledgment discharge" {
    var outcome = own.MustUse(u32, "inspect outcome").init(7);
    defer outcome.deinit();
    var raw: u32 = undefined;
    outcome.take(&raw);
    try t.expectEqual(@as(u32, 7), raw);
    var ignored = own.MustUse(bool, "inspect flag").init(false);
    defer ignored.deinit();
    ignored.acknowledge("false result intentionally ignored by this fixture");
}
