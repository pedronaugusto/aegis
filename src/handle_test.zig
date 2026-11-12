const std = @import("std");
const shake = @import("shakedown");
const root = @import("root.zig");
const h = root.handle;
const Region = root.Region;
const t = std.testing;
const Tag = struct {};
fn ignore(_: *u32) void {}
fn instance() h.Instance {
    return .{ .namespace = 7, .serial = 1 };
}
/// The keyed pool, as a growing map and on a fixed buffer of `n` slots.
const Keys = h.SlotPool(u32, Tag, .{ .generation = u64 });
fn reserved(bytes: usize) !Region {
    return Region.reserve(.init(bytes));
}
fn Slots(comptime P: type, comptime n: usize) type {
    return struct {
        buffer: [n * @sizeOf(P.Slot)]u8 align(@alignOf(P.Slot)) = undefined,
        fn region(self: *@This()) Region {
            return .fixed(&self.buffer);
        }
    };
}
fn dense(comptime T: type) !h.DenseSlotMap(T, Tag) {
    return .init(.{ .slots = try reserved(1 << 20), .values = try reserved(1 << 20), .keys = try reserved(1 << 20) }, instance());
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
    var slots: Slots(Keys, 2) = .{};
    var other_slots: Slots(Keys, 2) = .{};
    var domain = h.Domain.init(99);
    var p = try Keys.init(slots.region(), try domain.issue());
    defer p.deinit(ignore);
    var other = try Keys.init(other_slots.region(), try domain.issue());
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
    try t.expectEqual(key, try p.handleOf(try p.get(key)));
    var out: u32 = undefined;
    try p.remove(key, &out);
    try t.expectEqual(@as(u32, 17), out);
    try t.expectError(error.InvalidKey, p.remove(key, &out));
    try t.expectError(error.InvalidKey, p.handleOf(&p.slots[0].value));
    value = 18;
    const next = try p.insert(&value);
    try t.expect(next.generation != key.generation);
    try t.expectEqual(key.index, next.index);
    try t.expectError(error.InvalidKey, p.get(key));
    p.clear(ignore);
    try t.expectError(error.InvalidKey, p.get(next));
    try t.expectError(error.InvalidInstance, Keys.init(slots.region(), .{ .namespace = 7, .serial = 0 }));
}

test "A8 a value borrow survives growth, and dense swaps fix both links" {
    var map = try Keys.init(try reserved(64 << 20), instance());
    defer map.deinit(ignore);
    var one: u32 = 1;
    const a = try map.insert(&one);
    const borrow = try map.get(a);
    for (0..100_000) |i| {
        var more: u32 = @intCast(i); // safe: below a hundred thousand
        _ = try map.insert(&more);
    }
    try t.expectEqual(borrow, try map.get(a));
    try t.expectEqual(@as(u32, 1), borrow.*);
    try t.expectEqual(@as(usize, 100_001), map.len());
    var d = try dense(u32);
    defer d.deinit(ignore);
    var keys: [20]@TypeOf(d).Key = undefined;
    for (&keys, 0..) |*key, i| {
        var value: u32 = @intCast(i); // safe: fixture has twenty entries
        key.* = try d.insert(&value);
    }
    var removed: u32 = undefined;
    try d.remove(keys[3], &removed);
    try t.expectEqual(@as(u32, 3), removed);
    try t.expectEqual(@as(u32, 19), d.items()[3]);
    try t.expectEqual(@as(u32, 19), (try d.get(keys[19])).*);
    try t.expect(!d.contains(keys[3]));
    for (keys, 0..) |key, i| {
        if (i == 3) continue;
        try t.expectEqual(@as(u32, @intCast(i)), (try d.get(key)).*); // safe: fixture index fits u32
    }
    try t.expectError(error.AliasedStorage, d.remove(keys[19], try d.get(keys[19])));
}

const Resource = struct {
    allocation: []u8,
    gpa: std.mem.Allocator,
    pub fn moveInto(self: *Resource, destination: *Resource) void {
        destination.* = self.*;
        self.* = undefined;
    }
    pub fn cleanup(self: *Resource) void {
        self.gpa.free(self.allocation);
        self.* = undefined;
    }
};
fn allocated(comptime is_dense: bool, gpa: std.mem.Allocator) !void {
    var map = if (is_dense) try dense(Resource) else try h.SlotPool(Resource, Tag, .{ .generation = u64 }).init(try reserved(1 << 20), instance());
    defer map.deinit(Resource.cleanup);
    const key = try acquire(gpa, &map, 8);
    _ = try acquire(gpa, &map, 2);
    var detached: Resource = undefined;
    try map.remove(key, &detached);
    detached.cleanup();
    _ = try acquire(gpa, &map, 4);
    map.clear(Resource.cleanup);
}
fn acquire(gpa: std.mem.Allocator, map: anytype, n: usize) !@typeInfo(@TypeOf(map)).pointer.child.Key {
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
    var map = try Keys.init(try reserved(1 << 20), instance());
    defer map.deinit(ignore);
    var secondary = h.SecondaryMap(Keys, u32).init(t.allocator, try reserved(1 << 20));
    defer secondary.deinit(ignore);
    var value: u32 = 9;
    const old = try map.insert(&value);
    value = 44;
    try secondary.put(&map, old, &value);
    const borrow = try secondary.get(&map, old);
    try t.expectEqual(@as(u32, 44), borrow.*);
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
    var slots: Slots(Keys, 8) = .{};
    var p = try Keys.init(slots.region(), instance());
    var keys: [8]?Keys.Key = @splat(null);
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
        try t.expectEqual(count, p.len());
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
    const P = h.SlotPool(usize, Tag, .{ .generation = u64 });
    var slots: Slots(P, 1) = .{};
    var p = try P.init(slots.region(), instance());
    try t.expectError(error.AliasedStorage, p.insert(&p.used));
    try t.expectEqual(@as(usize, 0), p.len());
    var source: usize = 8;
    const key = try p.insert(&source);
    try t.expectError(error.AliasedStorage, p.remove(key, &p.used));
    try t.expectEqual(@as(usize, 1), p.len());
    try t.expectEqual(@as(usize, 8), (try p.get(key)).*);
}

fn secondaryAllocations(gpa: std.mem.Allocator) !void {
    var slots: Slots(Keys, 4) = .{};
    var primary = try Keys.init(slots.region(), instance());
    defer primary.deinit(ignore);
    var secondary = h.SecondaryMap(Keys, Resource).init(gpa, try reserved(1 << 20));
    defer secondary.deinit(Resource.cleanup);
    for (0..4) |_| {
        var seed: u32 = 1;
        const key = try primary.insert(&seed);
        try putResource(gpa, &secondary, &primary, key);
    }
    var removed: u32 = undefined;
    const first: Keys.Key = .{ .instance = instance(), .index = 0, .generation = 1 };
    try primary.remove(first, &removed);
    secondary.prune(&primary, Resource.cleanup);
}
fn putResource(gpa: std.mem.Allocator, secondary: *h.SecondaryMap(Keys, Resource), primary: *const Keys, key: Keys.Key) !void {
    var value: Resource = .{ .gpa = gpa, .allocation = try gpa.alloc(u8, 3) };
    errdefer value.cleanup();
    try secondary.put(primary, key, &value);
}
test "A8 secondary owning growth every allocation failure and stale prune cleanup" {
    var nr = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(nr.allocator(), secondaryAllocations, .{});
}
fn denseTrace(_: void, c: *shake.Case) !void {
    var map = try dense(u32);
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

test "A8 a refused commit and a full region preserve live keys, values and borrows" {
    var map = try Keys.init(try reserved(1 << 20), instance());
    defer map.deinit(ignore);
    var value: u32 = 23;
    const key = try map.insert(&value);
    const borrow = try map.get(key);
    // The first commit holds 64 KiB of slots; the next insert past them needs a commit.
    while (map.capacity() * @sizeOf(Keys.Slot) + @sizeOf(Keys.Slot) <= map.region.committed().raw()) {
        var filler: u32 = 0;
        _ = try map.insert(&filler);
    }
    const live = map.len();
    Region.testing.refuse_commit = true;
    defer Region.testing.refuse_commit = false;
    value = 24;
    try t.expectError(error.OutOfMemory, map.insert(&value));
    try t.expectEqual(@as(u32, 24), value);
    try t.expectEqual(live, map.len());
    try t.expectEqual(borrow, try map.get(key));
    try t.expectEqual(@as(u32, 23), borrow.*);

    var slots: Slots(Keys, 1) = .{};
    var full = try Keys.init(slots.region(), instance());
    defer full.deinit(ignore);
    _ = try full.insert(&value);
    try t.expectError(error.LimitExceeded, full.insert(&value));
}

const owners = @import("own.zig");
const OwnedResource = owners.Owned(Resource, Resource.cleanup);
fn allocatedOwned(comptime is_dense: bool, gpa: std.mem.Allocator) !void {
    var map = if (is_dense) try dense(OwnedResource) else try h.SlotPool(OwnedResource, Tag, .{ .generation = u64 }).init(try reserved(1 << 20), instance());
    defer map.deinit(OwnedResource.deinit);
    var source = OwnedResource.init(.{ .gpa = gpa, .allocation = try gpa.dupe(u8, "owned") });
    const key = blk: {
        errdefer source.deinit();
        _ = source.borrow(); // Bind the Debug address before explicit transfer.
        break :blk try map.insert(&source);
    };
    try t.expectEqualStrings("owned", (try map.get(key)).borrow().allocation);
    for (0..64) |_| {
        var more = OwnedResource.init(.{ .gpa = gpa, .allocation = &.{} });
        _ = try map.insert(&more); // Growth moves no owner: the bound address stays.
    }
    try t.expectEqualStrings("owned", (try map.get(key)).borrow().allocation);
    var detached: OwnedResource = undefined;
    try map.remove(key, &detached);
    detached.deinit();
    try t.expect(!map.contains(key));
}
fn allocatedOwnedSlots(gpa: std.mem.Allocator) !void {
    try allocatedOwned(false, gpa);
}
fn allocatedOwnedDense(gpa: std.mem.Allocator) !void {
    try allocatedOwned(true, gpa);
}
test "A8 published A7 bound Owned moves, growth, removal and allocation failure cleanup" {
    var nr = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(nr.allocator(), allocatedOwnedSlots, .{});
    try t.checkAllAllocationFailures(nr.allocator(), allocatedOwnedDense, .{});
}

// A pool with a two-bit generation runs every slot out of generations, so retirement is reached in a few steps.
const Narrow = h.SlotPool(u32, Tag, .{ .generation = u2 });
test "A8 narrow generations retire a slot that used them all and removals stale every older key" {
    var slots: Slots(Narrow, 2) = .{};
    var p = try Narrow.init(slots.region(), instance());
    var previous: [6]Narrow.Key = undefined;
    for (0..6) |i| {
        var value: u32 = 31;
        const key = try p.insert(&value);
        previous[i] = key;
        for (previous[0..i]) |old| try t.expect(!p.contains(old));
        var removed: u32 = undefined;
        try p.remove(key, &removed);
    }
    var value: u32 = 11;
    try t.expectError(error.LimitExceeded, p.insert(&value));
    try t.expectEqual(@as(u32, 11), value);
    p.clear(ignore);
    try t.expectError(error.LimitExceeded, p.insert(&value));
    try t.expectEqual(@as(usize, 2), p.retired);
}

test "A8 narrow generations retire a slot through clear" {
    var slots: Slots(Narrow, 1) = .{};
    var p = try Narrow.init(slots.region(), instance());
    for (0..3) |_| {
        var value: u32 = 1;
        const key = try p.insert(&value);
        p.clear(ignore);
        try t.expect(!p.contains(key));
    }
    var value: u32 = 2;
    try t.expectError(error.LimitExceeded, p.insert(&value));
    try t.expectEqual(@as(usize, 1), p.retired);
}

test "SlotPool indexes are four bytes, reuse the newest freed slot and never move a value" {
    const P = h.SlotPool(u64, Tag, .{});
    try t.expectEqual(4, @sizeOf(P.Handle));
    try t.expectEqual(4, @sizeOf(P.OptionalHandle));
    var pool = P.init(try reserved(64 << 20));
    defer pool.deinit();
    const first = try pool.alloc(7);
    const kept = pool.get(first);
    var handles: [100_000]P.Handle = undefined;
    for (&handles, 0..) |*handle, i| handle.* = try pool.alloc(i);
    try t.expectEqual(kept, pool.get(first));
    try t.expectEqual(@as(u64, 7), kept.*);
    pool.free(handles[10]);
    pool.free(handles[20]);
    try t.expectEqual(handles[20], try pool.alloc(1));
    try t.expectEqual(handles[10], try pool.alloc(2));
    try t.expectEqual(first, pool.handleOf(kept));
    try t.expectEqual(@as(usize, 100_001), pool.len());
    const optional: P.OptionalHandle = .some(first);
    try t.expectEqual(first, optional.unwrap().?);
    try t.expectEqual(@as(?P.Handle, null), P.OptionalHandle.none.unwrap());
    const built = try pool.create();
    built.value.* = @backingInt(built.handle);
    try t.expectEqual(@as(u64, @backingInt(built.handle)), pool.get(built.handle).*);
    pool.recycleAll();
    try t.expectEqual(@as(usize, 0), pool.len());
    try t.expectEqual(first, try pool.alloc(9));
}

test "SlotPool on a fixed buffer runs out at its end" {
    var buffer: [64]u8 align(8) = undefined;
    const P = h.SlotPool(u32, Tag, .{});
    var pool = P.init(Region.fixed(&buffer));
    defer pool.deinit();
    var n: usize = 0;
    while (pool.alloc(1)) |_| n += 1 else |err| try t.expectEqual(error.LimitExceeded, err);
    try t.expectEqual(64 / @sizeOf(P.Slot), n);
}

/// The indexed pool against a model: a value per live handle, and the free order.
fn slotTrace(_: void, case: *shake.Case) anyerror!void {
    const P = h.SlotPool(u32, Tag, .{});
    var buffer: [512]u8 align(8) = undefined;
    var pool = P.init(if (shake.gen.boolean(case.source)) try reserved(1 << 20) else Region.fixed(&buffer));
    defer pool.deinit();
    var live: std.ArrayList(struct { handle: P.Handle, value: u32 }) = .empty;
    defer live.deinit(t.allocator);
    var freed: std.ArrayList(P.Handle) = .empty;
    defer freed.deinit(t.allocator);
    for (0..128) |step| {
        switch (shake.gen.intRange(case.source, u8, 0, 3)) {
            0, 1 => if (pool.alloc(@intCast(step))) |handle| {
                if (freed.pop()) |expected| try t.expectEqual(expected, handle);
                try live.append(t.allocator, .{ .handle = handle, .value = @intCast(step) });
            } else |err| {
                try t.expectEqual(error.LimitExceeded, err);
                try t.expectEqual(@as(usize, 0), freed.items.len);
            },
            2 => if (live.items.len != 0) {
                const at = shake.gen.intRange(case.source, usize, 0, live.items.len - 1);
                const gone = live.swapRemove(at);
                pool.free(gone.handle);
                try freed.append(t.allocator, gone.handle);
            },
            3 => if (shake.gen.intRange(case.source, u8, 0, 15) == 0) {
                pool.recycleAll();
                live.clearRetainingCapacity();
                freed.clearRetainingCapacity();
            },
            else => unreachable,
        }
        try t.expectEqual(live.items.len, pool.len());
        for (live.items) |entry| try t.expectEqual(entry.value, pool.get(entry.handle).*);
    }
}

test "SlotPool generated traces of allocs, frees and recycles agree with a model" {
    try shake.check(t.allocator, {}, slotTrace, .{ .cases = 512, .seed = 0x5107 });
}

test "Offset names a byte of a region's live memory, checked in every build" {
    const O = h.Offset(Tag, u16);
    var r = try reserved(1 << 20);
    defer r.deinit();
    _ = try r.push(u8, 3);
    const word = try r.create(u32);
    word.* = 0xfeed;
    const at = try O.of(&r, word);
    try t.expectEqual(@as(u16, 4), at.raw());
    try t.expectEqual(word, try at.get(&r, u32));
    try t.expectError(error.OutOfBounds, O.fromRaw(5).get(&r, u32));
    try t.expectError(error.OutOfBounds, O.fromRaw(6).get(&r, u32));
    _ = try r.push(u8, 70_000);
    const far = try r.create(u8);
    try t.expectError(error.OutOfBounds, O.of(&r, far));
    try t.expectEqual(@as(u32, 70_008), (try h.Offset(Tag, u32).of(&r, far)).raw());
}

const Runs = h.RunPool(u32, Tag);
fn runs() !Runs {
    return .init(try reserved(64 << 20), try reserved(64 << 20));
}

test "RunPool fits first in index order, coalesces, and grows at the end" {
    var p = try runs();
    defer p.deinit();
    const a = try p.alloc(4);
    const b = try p.alloc(4);
    const c = try p.alloc(4);
    try t.expectEqual(@as(u32, 8), c.start.raw());
    @memset(p.slice(b), 7);
    const kept = p.slice(b).ptr;
    p.free(a);
    p.free(c); // the last run: the end comes back to it
    try t.expectEqual(@as(usize, 4), p.used());
    const small = try p.alloc(3);
    try t.expectEqual(@as(u32, 0), small.start.raw());
    const big = try p.alloc(6); // no free span holds six: the end grows
    try t.expectEqual(@as(u32, 8), big.start.raw());
    p.free(small);
    p.free(b); // joins the span before it: [0, 8) free
    const joined = try p.alloc(8);
    try t.expectEqual(@as(u32, 0), joined.start.raw());
    try t.expectEqual(kept, p.slice(joined)[4..].ptr);
    // A run that ends the pool grows in place; one followed by a free span grows into it.
    const grown = try p.realloc(big, 10);
    try t.expectEqual(big.start, grown.start);
    const shrunk = try p.realloc(joined, 2);
    try t.expectEqual(joined.start, shrunk.start);
    const regrown = try p.realloc(shrunk, 8);
    try t.expectEqual(joined.start, regrown.start);
    try t.expectEqual(@as(usize, 18), p.used());
    p.recycleAll();
    try t.expectEqual(@as(usize, 0), p.used());
    try t.expectEqual(@as(u32, 0), (try p.alloc(1)).start.raw());
}

test "RunPool keeps thousands of free spans in its tree and gives them all back" {
    var p = try runs();
    defer p.deinit();
    var all: [5000]Runs.Run = undefined;
    for (&all, 0..) |*run, i| {
        run.* = try p.alloc(@intCast(i % 7 + 1));
        @memset(p.slice(run.*), @intCast(i));
    }
    // Every other run freed: as many spans, none adjacent, which splits the tree's nodes.
    for (all, 0..) |run, i| if (i % 2 == 0) p.free(run);
    for (all, 0..) |run, i| if (i % 2 == 1) for (p.slice(run)) |item| try t.expectEqual(@as(u32, @intCast(i)), item);
    // Small runs fit the lowest spans first.
    const first = try p.alloc(1);
    try t.expectEqual(@as(u32, 0), first.start.raw());
    p.free(first);
    var i: usize = all.len;
    while (i > 1) {
        i -= 2;
        p.free(all[i + 1]);
    }
    try t.expectEqual(@as(usize, 0), p.used());
    try t.expectEqual(@as(u32, 0), (try p.alloc(3)).start.raw());
}

/// The run pool against a model: who owns each item below the end, and what each run holds.
fn runTrace(_: void, case: *shake.Case) anyerror!void {
    var p = try runs();
    defer p.deinit();
    const gpa = t.allocator;
    var owner: std.ArrayList(u32) = .empty; // run id + 1 per item, zero when free
    defer owner.deinit(gpa);
    const Live = struct { run: Runs.Run, id: u32 };
    var live: std.ArrayList(Live) = .empty;
    defer live.deinit(gpa);
    var next_id: u32 = 1;
    for (0..160) |_| {
        switch (shake.gen.intRange(case.source, u8, 0, 9)) {
            0...3 => {
                const n = shake.gen.intRange(case.source, u32, 0, 24);
                const expected = fit(owner.items, n);
                const run = try p.alloc(n);
                if (n == 0) continue;
                try t.expectEqual(expected, run.start.raw());
                try claim(&owner, run, next_id);
                @memset(p.slice(run), next_id);
                try live.append(gpa, .{ .run = run, .id = next_id });
                next_id += 1;
            },
            4...6 => if (live.items.len != 0) {
                const gone = live.swapRemove(shake.gen.intRange(case.source, usize, 0, live.items.len - 1));
                p.free(gone.run);
                for (owner.items[gone.run.start.raw()..][0..gone.run.len]) |*item| item.* = 0;
            },
            7, 8 => if (live.items.len != 0) {
                const at = shake.gen.intRange(case.source, usize, 0, live.items.len - 1);
                const old = live.items[at].run;
                const n = shake.gen.intRange(case.source, u32, 1, 32);
                const start = old.start.raw();
                const after = start + old.len;
                const free_after = gap(owner.items, after);
                const in_place = n <= old.len or after == owner.items.len or free_after >= n - old.len;
                const expected = if (in_place) start else fit(owner.items, n);
                const run = try p.realloc(old, n);
                try t.expectEqual(expected, run.start.raw());
                for (owner.items[start..][0..old.len]) |*item| item.* = 0;
                try claim(&owner, run, live.items[at].id);
                for (p.slice(run)[0..@min(n, old.len)]) |item| try t.expectEqual(live.items[at].id, item);
                @memset(p.slice(run), live.items[at].id);
                live.items[at].run = run;
            },
            9 => if (shake.gen.intRange(case.source, u8, 0, 7) == 0) {
                p.recycleAll();
                owner.clearRetainingCapacity();
                live.clearRetainingCapacity();
            },
            else => unreachable,
        }
        // The end is the last owned item's: free items at the end go back to it.
        while (owner.items.len != 0 and owner.items[owner.items.len - 1] == 0) _ = owner.pop();
        var used: usize = 0;
        for (live.items) |entry| {
            used += entry.run.len;
            for (p.slice(entry.run)) |item| try t.expectEqual(entry.id, item);
        }
        try t.expectEqual(used, p.used());
        try t.expectEqual(owner.items.len, p.aegis_end);
    }
}

/// First fit in the model: the lowest free gap of `n` items, else the gap ending the items, else the end.
fn fit(owner: []const u32, n: u32) u32 {
    var start: usize = 0;
    while (start < owner.len) {
        if (owner[start] != 0) {
            start += 1;
            continue;
        }
        const len = gap(owner, start);
        if (len >= n) return @intCast(start);
        start += len;
    }
    var tail = owner.len;
    while (tail > 0 and owner[tail - 1] == 0) tail -= 1;
    return @intCast(tail);
}

fn gap(owner: []const u32, start: usize) usize {
    var end = start;
    while (end < owner.len and owner[end] == 0) end += 1;
    return end - start;
}

fn claim(owner: *std.ArrayList(u32), run: Runs.Run, id: u32) !void {
    const end = run.start.raw() + run.len;
    if (owner.items.len < end) try owner.appendNTimes(t.allocator, 0, end - owner.items.len);
    for (owner.items[run.start.raw()..end]) |*item| {
        try t.expectEqual(@as(u32, 0), item.*);
        item.* = id;
    }
}

test "RunPool generated traces of allocs, reallocs, frees and recycles agree with a model" {
    try shake.check(t.allocator, {}, runTrace, .{ .cases = 512, .seed = 0x2b9 });
}
