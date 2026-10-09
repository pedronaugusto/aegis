const std = @import("std");
const shake = @import("shakedown");
const b = @import("bounded");
const own = @import("own");
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

test "A7 containers explicitly move bound Owned values and retain cleanup identity" {
    const O = own.Owned(Resource, Resource.deinit);
    var cleaned: usize = 0;
    var queue: b.Queue(O, 2) = .init;
    defer queue.deinit(O.deinit);
    var owner = O.init(.{ .gpa = t.allocator, .bytes = try t.allocator.alloc(u8, 1), .cleaned = &cleaned });
    owner.borrowMut().bytes[0] = 42;
    try queue.push(&owner);
    try t.expectEqual(@as(u8, 42), (try queue.peek()).borrow().bytes[0]);
    var taken: O = undefined;
    try queue.pop(&taken);
    try t.expectEqual(@as(u8, 42), taken.borrow().bytes[0]);
    var buffer = try b.Buffer(O).initAllocated(t.allocator, 1, 2);
    defer buffer.deinit(O.deinit);
    try buffer.append(&taken);
    try t.expectEqual(@as(u8, 42), buffer.items()[0].borrow().bytes[0]);
    try buffer.reserve(2);
    try t.expectEqual(@as(u8, 42), buffer.items()[0].borrow().bytes[0]);
    buffer.clear(O.deinit);
    try t.expectEqual(@as(usize, 1), cleaned);
}

fn ringConstruction(gpa: std.mem.Allocator) !void {
    const O = own.Owned(Resource, Resource.deinit);
    var cleaned: usize = 0;
    var queue = try b.RingBuffer(O).initAllocated(gpa, 2, 4);
    defer queue.deinit(O.deinit);
    for (0..2) |i| {
        var owner = O.init(.{ .gpa = gpa, .bytes = try gpa.alloc(u8, 1), .cleaned = &cleaned });
        owner.borrowMut().bytes[0] = @intCast(i); // safe: loop index is 0 or 1
        try queue.push(&owner);
    }
    var taken: O = undefined;
    try queue.pop(&taken);
    taken.deinit();
    var next = O.init(.{ .gpa = gpa, .bytes = try gpa.alloc(u8, 1), .cleaned = &cleaned });
    next.borrowMut().bytes[0] = 2;
    try queue.push(&next);
    const first = (try queue.peek()).borrow().bytes.ptr;
    queue.reserve(4) catch |err| {
        try t.expect(first == (try queue.peek()).borrow().bytes.ptr);
        try t.expectEqual(@as(usize, 2), queue.len());
        return err;
    };
    try queue.pop(&taken);
    try t.expectEqual(@as(u8, 1), taken.borrow().bytes[0]);
    taken.deinit();
    try queue.pop(&taken);
    try t.expectEqual(@as(u8, 2), taken.borrow().bytes[0]);
    taken.deinit();
    try t.expectEqual(@as(usize, 3), cleaned);
}
test "A7 dynamic FIFO wrap growth ownership and every allocation failure" {
    var no_resize = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(no_resize.allocator(), ringConstruction, .{});
    var storage: [3]u32 = undefined;
    var queue = try b.QueueBuffer(u32).initBuffer(&storage);
    defer queue.deinit(noop);
    try t.expectError(error.InvalidCapacity, b.RingBuffer(u32).initBuffer(&.{}));
    try t.expectError(error.CapacityExceeded, queue.reserve(4));
    var x: u32 = 3;
    try queue.push(&x);
    try queue.pop(&x);
    try t.expectEqual(@as(u32, 3), x);
}

const aegis = @import("../root.zig");
fn secretCleanup(value: *aegis.Secret([32]u8)) void {
    value.deinit();
}
fn bytesCleanup(value: *aegis.SecretBytes) void {
    value.deinit();
}
test "A7 Owned preserves nested secret transfer erasure and full-capacity cleanup" {
    const S = own.Owned(aegis.Secret([32]u8), secretCleanup);
    var secret = S.init(.init(@splat(42)));
    var moved: S = undefined;
    secret.moveInto(&moved);
    for (std.mem.asBytes(&secret.data)) |byte| try t.expectEqual(@as(u8, 0), byte);
    var raw: aegis.Secret([32]u8) = undefined;
    moved.take(&raw);
    for (std.mem.asBytes(&moved.data)) |byte| try t.expectEqual(@as(u8, 0), byte);
    raw.deinit();
    const B = own.Owned(aegis.SecretBytes, bytesCleanup);
    var bytes = B.init(try aegis.SecretBytes.init(t.allocator, 64));
    try bytes.borrowMut().replace("key");
    var final: B = undefined;
    bytes.moveInto(&final);
    for (std.mem.asBytes(&bytes.data)) |byte| try t.expectEqual(@as(u8, 0), byte);
    try t.expectEqual(@as(usize, 64), final.borrow().capacity());
    final.deinit();
}
