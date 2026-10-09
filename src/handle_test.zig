const std = @import("std");
const shake = @import("shakedown");
const h = @import("root.zig").handle;
const t = std.testing;
const Tag = struct {};
fn ignore(_: *u32) void {}
fn instance() h.Instance {
    return .{ .namespace = 7, .serial = 1 };
}

test "A8 domains exhaust without wrapping and checked positions revalidate length" {
    var d = h.Domain.init(123);
    const a = try d.issue();
    const b = try d.issue();
    try t.expect(!a.eql(b));
    d.last = std.math.maxInt(u64);
    try t.expectError(error.InstanceExhausted, d.issue());
    try t.expectEqual(std.math.maxInt(u64), d.last);
    const I = h.Index(Tag, u16);
    var values = [_]u32{ 2, 3 };
    const index = try I.from(1, 2);
    try t.expectEqual(@as(u32, 3), (try index.get(values[0..])).*);
    try t.expectError(error.OutOfBounds, index.get(values[0..1]));
    try t.expectError(error.OutOfBounds, I.from(2, 2));
    const view: []const u32 = &values;
    try t.expect(@TypeOf(try index.get(view)) == *const u32);
}

test "A8 pool stale forged cross-instance and clear keys fail in every mode" {
    const P = h.Pool(u32, Tag);
    var slots: [2]P.Slot = undefined;
    var other_slots: [2]P.Slot = undefined;
    var domain = h.Domain.init(99);
    var p = try P.initBuffer(&slots, try domain.issue());
    defer p.deinit(ignore);
    var other = try P.initBuffer(&other_slots, try domain.issue());
    defer other.deinit(ignore);
    var value: u32 = 17;
    const key = try p.insert(&value);
    try t.expectError(error.InvalidKey, other.get(key));
    var forged = key;
    forged.instance.namespace += 1;
    try t.expectError(error.InvalidKey, p.get(forged));
    forged = key;
    forged.index = 10;
    try t.expectError(error.InvalidKey, p.get(forged));
    forged = key;
    forged.generation += 1;
    try t.expectError(error.InvalidKey, p.get(forged));
    try t.expectError(error.AliasedStorage, p.remove(key, try p.get(key)));
    try t.expectError(error.AliasedStorage, p.insert(try p.get(key)));
    var out: u32 = undefined;
    try p.remove(key, &out);
    try t.expectEqual(@as(u32, 17), out);
    try t.expectError(error.InvalidKey, p.remove(key, &out));
    value = 18;
    const next = try p.insert(&value);
    try t.expect(next.generation != key.generation);
    try t.expectError(error.InvalidKey, p.get(key));
    p.clear(ignore);
    try t.expectError(error.InvalidKey, p.get(next));
    try t.expectError(error.InvalidInstance, P.initBuffer(&slots, .{ .namespace = 7, .serial = 0 }));
}

test "A8 growth and dense swap preserve keys and fix both links" {
    var map = try h.SlotMap(u32, Tag).init(t.allocator, instance(), .{});
    defer map.deinit(ignore);
    var one: u32 = 1;
    const a = try map.insert(&one);
    try map.reserve(64);
    try t.expectEqual(@as(u32, 1), (try map.get(a)).*);
    var dense = try h.Dense(u32, Tag).init(t.allocator, instance(), .{ .max_capacity = 64 });
    defer dense.deinit(ignore);
    var keys: [20]@TypeOf(dense).Key = undefined;
    for (&keys, 0..) |*key, i| {
        var value: u32 = @intCast(i); // safe: fixture has twenty entries
        key.* = try dense.insert(&value);
    }
    var removed: u32 = undefined;
    try dense.remove(keys[3], &removed);
    try t.expectEqual(@as(u32, 3), removed);
    try t.expectEqual(@as(u32, 19), dense.items()[3]);
    try t.expectEqual(@as(u32, 19), (try dense.get(keys[19])).*);
    try t.expect(!dense.contains(keys[3]));
    try dense.reserve(64);
    for (keys, 0..) |key, i| {
        if (i == 3) continue;
        try t.expectEqual(@as(u32, @intCast(i)), (try dense.get(key)).*); // safe: fixture index fits u32
    }
    try t.expectError(error.AliasedStorage, dense.remove(keys[19], try dense.get(keys[19])));
}

const Resource = struct {
    allocation: []u8,
    gpa: std.mem.Allocator,
    pub fn moveInto(self: *@This(), destination: *@This()) void {
        destination.* = self.*;
        self.* = undefined;
    }
    pub fn cleanup(self: *@This()) void {
        self.gpa.free(self.allocation);
        self.* = undefined;
    }
};
fn allocated(comptime dense: bool, gpa: std.mem.Allocator) !void {
    const Map = if (dense) h.Dense(Resource, Tag) else h.SlotMap(Resource, Tag);
    var map = try Map.init(gpa, instance(), .{ .capacity = 1, .max_capacity = 16 });
    defer map.deinit(Resource.cleanup);
    const key = try acquire(&map, gpa, 8);
    try map.reserve(16);
    var detached: Resource = undefined;
    try map.remove(key, &detached);
    detached.cleanup();
    _ = try acquire(&map, gpa, 4);
    map.clear(Resource.cleanup);
}
fn acquire(map: anytype, gpa: std.mem.Allocator, n: usize) !@typeInfo(@TypeOf(map)).pointer.child.Key {
    var item: Resource = .{ .gpa = gpa, .allocation = try gpa.alloc(u8, n) };
    errdefer item.cleanup();
    return map.insert(&item);
}
fn allocatedSlots(gpa: std.mem.Allocator) !void {
    return allocated(false, gpa);
}
fn allocatedDense(gpa: std.mem.Allocator) !void {
    return allocated(true, gpa);
}
test "A8 all allocation failures and owning cleanup on NoResize" {
    var nr = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(nr.allocator(), allocatedSlots, .{});
    try t.checkAllAllocationFailures(nr.allocator(), allocatedDense, .{});
}

test "A8 secondary exact-key witness rejects stale associations and prune cleans" {
    var map = try h.SlotMap(u32, Tag).init(t.allocator, instance(), .{});
    defer map.deinit(ignore);
    var secondary = h.SecondaryMap(@TypeOf(map).Key, u32).init(t.allocator);
    defer secondary.deinit(ignore);
    var value: u32 = 9;
    const old = try map.insert(&value);
    value = 44;
    try secondary.put(&map, old, &value);
    try t.expectEqual(@as(u32, 44), (try secondary.get(&map, old)).*);
    try map.remove(old, &value);
    const new = try map.insert(&value);
    try t.expectError(error.InvalidKey, secondary.get(&map, old));
    try t.expectError(error.Missing, secondary.get(&map, new));
    value = 45;
    try secondary.put(&map, new, &value);
    secondary.prune(&map, ignore);
    try t.expectEqual(@as(u32, 45), (try secondary.get(&map, new)).*);
    try t.expectError(error.Missing, secondary.remove(old, &value));
}

fn trace(_: void, c: *shake.Case) !void {
    const P = h.Pool(u32, Tag);
    var slots: [8]P.Slot = undefined;
    var p = try P.initBuffer(&slots, instance());
    var keys: [8]?P.Key = @splat(null);
    var oracle: [8]u32 = @splat(0);
    var count: usize = 0;
    for (0..128) |_| {
        const i = shake.gen.intRange(c.source, usize, 0, 7);
        if (keys[i]) |key| {
            try t.expectEqual(oracle[i], (try p.get(key)).*);
            var removed: u32 = undefined;
            try p.remove(key, &removed);
            try t.expectEqual(oracle[i], removed);
            try t.expect(!p.contains(key));
            keys[i] = null;
            count -= 1;
        } else {
            var value = shake.gen.int(c.source, u32);
            oracle[i] = value;
            keys[i] = try p.insert(&value);
            count += 1;
        }
        try t.expectEqual(count, p.len);
        for (keys, oracle) |key, expected| if (key) |live| {
            try t.expectEqual(expected, (try p.get(live)).*);
        };
    }
    p.deinit(ignore);
}
test "A8 generated churn has independent live-set oracle" {
    try shake.check(t.allocator, {}, trace, .{ .cases = 128 });
}

test "A8 transfers reject aliasing the owner metadata before mutation" {
    const P = h.Pool(usize, Tag);
    var slots: [1]P.Slot = undefined;
    var p = try P.initBuffer(&slots, instance());
    try t.expectError(error.AliasedStorage, p.insert(&p.len));
    try t.expectEqual(@as(usize, 0), p.len);
    var source: usize = 8;
    const key = try p.insert(&source);
    try t.expectError(error.AliasedStorage, p.remove(key, &p.len));
    try t.expectEqual(@as(usize, 1), p.len);
    try t.expectEqual(@as(usize, 8), (try p.get(key)).*);
}

fn secondaryAllocations(gpa: std.mem.Allocator) !void {
    const Primary = h.Pool(u32, Tag);
    var slots: [4]Primary.Slot = undefined;
    var primary = try Primary.initBuffer(&slots, instance());
    defer primary.deinit(ignore);
    var secondary = h.SecondaryMap(Primary.Key, Resource).init(gpa);
    defer secondary.deinit(Resource.cleanup);
    for (0..4) |_| {
        var seed: u32 = 1;
        const key = try primary.insert(&seed);
        try putResource(&secondary, &primary, key, gpa);
    }
    var removed: u32 = undefined;
    const first: Primary.Key = .{ .instance = instance(), .index = 0, .generation = 1 };
    try primary.remove(first, &removed);
    secondary.prune(&primary, Resource.cleanup);
}
fn putResource(secondary: anytype, primary: anytype, key: @typeInfo(@TypeOf(primary)).pointer.child.Key, gpa: std.mem.Allocator) !void {
    var value: Resource = .{ .gpa = gpa, .allocation = try gpa.alloc(u8, 3) };
    errdefer value.cleanup();
    try secondary.put(primary, key, &value);
}
test "A8 secondary owning growth every allocation failure and stale prune cleanup" {
    var nr = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(nr.allocator(), secondaryAllocations, .{});
}
fn denseTrace(_: void, c: *shake.Case) !void {
    var map = try h.Dense(u32, Tag).init(t.allocator, instance(), .{ .max_capacity = 8 });
    defer map.deinit(ignore);
    var keys: [8]?@TypeOf(map).Key = @splat(null);
    var values: [8]u32 = @splat(0);
    var count: usize = 0;
    for (0..128) |_| {
        const i = shake.gen.intRange(c.source, usize, 0, 7);
        if (keys[i]) |key| {
            var removed: u32 = undefined;
            try map.remove(key, &removed);
            try t.expectEqual(values[i], removed);
            try t.expect(!map.contains(key));
            keys[i] = null;
            count -= 1;
        } else {
            var value = shake.gen.int(c.source, u32);
            values[i] = value;
            keys[i] = try map.insert(&value);
            count += 1;
        }
        try t.expectEqual(count, map.items().len);
        for (keys, values) |key, value| if (key) |live| {
            try t.expectEqual(value, (try map.get(live)).*);
        };
    }
}
test "A8 generated dense swaps preserve independent keyed values" {
    try shake.check(t.allocator, {}, denseTrace, .{ .cases = 128 });
}

test "A8 reserve admission failure preserves live keys values and borrows" {
    var failing = std.testing.FailingAllocator.init(t.allocator, .{});
    var map = try h.SlotMap(u32, Tag).init(failing.allocator(), instance(), .{ .capacity = 1, .max_capacity = 4 });
    defer map.deinit(ignore);
    var value: u32 = 23;
    const key = try map.insert(&value);
    const borrow = try map.get(key);
    failing.fail_index = failing.alloc_index;
    try t.expectError(error.OutOfMemory, map.reserve(4));
    try t.expectEqual(borrow, try map.get(key));
    try t.expectEqual(@as(u32, 23), borrow.*);
    value = 24;
    try t.expectError(error.OutOfMemory, map.insert(&value));
    try t.expectEqual(@as(u32, 24), value);
    try t.expectError(error.CapacityExceeded, map.reserve(5));
    try t.expectEqual(@as(usize, 1), map.len());
}
