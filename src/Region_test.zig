const std = @import("std");
const shake = @import("shakedown");
const Region = @import("root.zig").Region;
const bounded = @import("root.zig").bounded;
const t = std.testing;

fn limit(bytes: usize) bounded.Limit(usize) {
    return .init(bytes);
}

test "Region items never move across a million appends" {
    var r = try Region.reserve(limit(64 << 20));
    defer r.deinit();
    var items = try r.tail(u64);
    const first = try items.append(0);
    for (1..1_000_000) |i| _ = try items.append(i);
    try t.expectEqual(@intFromPtr(first), @intFromPtr(&items.items()[0]));
    const sealed = items.seal();
    try t.expectEqual(@as(usize, 1_000_000), sealed.len);
    for (sealed, 0..) |value, i| try t.expectEqual(@as(u64, i), value);
    try t.expectEqual(@as(usize, 8_000_000), r.used().raw());
    try t.expect(r.committed().raw() >= r.used().raw());
}

test "Region past its limit is LimitExceeded, and a refused commit OutOfMemory with the region unchanged" {
    var r = try Region.reserve(limit(100_000));
    defer r.deinit();
    // The limit is rounded up to whole pages, and the region holds exactly that.
    const capacity = r.capacity().raw();
    try t.expectEqual(std.mem.alignForward(usize, 100_000, std.heap.pageSize()), capacity);
    _ = try r.push(u8, capacity - 1);
    _ = try r.push(u8, 1);
    try t.expectError(error.LimitExceeded, r.push(u8, 1));
    try t.expectError(error.LimitExceeded, r.push(u64, std.math.maxInt(usize) / 4));
    try t.expectEqual(capacity, r.used().raw());
    try t.expectEqual(capacity, r.committed().raw());

    var s = try Region.reserve(limit(1 << 30));
    defer s.deinit();
    _ = try s.push(u8, 10);
    const used = s.used();
    const committed = s.committed();
    Region.testing.refuse_commit = true;
    defer Region.testing.refuse_commit = false;
    try t.expectError(error.OutOfMemory, s.push(u8, 1 << 20));
    try t.expectEqual(used, s.used());
    try t.expectEqual(committed, s.committed());
    Region.testing.refuse_commit = false;
    const later = try s.push(u8, 1 << 20);
    try t.expectEqual(@as(usize, 1 << 20), later.len);
}

test "Region on a fixed buffer fails at its end, aligned" {
    var buffer: [64]u8 align(8) = undefined;
    var r = Region.fixed(&buffer);
    defer r.deinit();
    const byte = try r.create(u8);
    const word = try r.create(u64);
    try t.expectEqual(@intFromPtr(&buffer) + 8, @intFromPtr(word));
    _ = byte;
    _ = try r.push(u64, 6);
    try t.expectError(error.LimitExceeded, r.create(u8));
    try t.expectEqual(@as(usize, 64), r.capacity().raw());
    r.trim();
    try t.expectEqual(@as(usize, 64), r.committed().raw());
}

test "Region marks release what was pushed after them, and trim gives pages back" {
    var r = try Region.reserve(limit(64 << 20));
    defer r.deinit();
    const kept = try r.dupe(u8, "kept");
    const outer = r.mark();
    _ = try r.push(u8, 8 << 20);
    const inner = r.mark();
    _ = try r.push(u8, 100);
    r.release(inner);
    try t.expectEqual(@as(usize, 4 + (8 << 20)), r.used().raw());
    r.release(outer);
    try t.expectEqual(@as(usize, 4), r.used().raw());
    try t.expectEqualStrings("kept", kept);
    const before = r.committed().raw();
    r.trim();
    try t.expect(r.committed().raw() < before);
    try t.expect(r.committed().raw() >= r.used().raw());
    // The pages trimmed come back on the next growth.
    const again = try r.push(u8, 1 << 20);
    @memset(again, 0xab);
    try t.expectEqualStrings("kept", kept);
}

test "Region allocator grows its top allocation in place and frees it" {
    var r = try Region.reserve(limit(16 << 20));
    defer r.deinit();
    const gpa = r.allocator();
    var list: std.ArrayList(u32) = .empty;
    try list.append(gpa, 1);
    const first = &list.items[0];
    for (2..100_000) |i| try list.append(gpa, @intCast(i));
    try t.expectEqual(@intFromPtr(first), @intFromPtr(&list.items[0]));
    list.deinit(gpa);
    try t.expectEqual(@as(usize, 0), r.used().raw());
    const text = try gpa.print("{d}", .{42});
    try t.expectEqualStrings("42", text);
    // A free below the top keeps its bytes until a release.
    const below = try gpa.alloc(u8, 4);
    _ = try gpa.alloc(u8, 4);
    gpa.free(below);
    try t.expectEqual(@as(usize, 10), r.used().raw());
}

/// The model: the live bytes as the region should hold them, the open marks, and the open tail.
const Model = struct {
    bytes: std.ArrayList(u8) = .empty,
    marks: std.ArrayList(struct { mark: Region.Mark, len: usize }) = .empty,
    tail: ?Region.Tail(u32) = null,
    tail_start: usize = 0,
};

fn trace(_: void, case: *shake.Case) anyerror!void {
    var buffer: [4096]u8 align(16) = undefined;
    var reserved = try Region.reserve(limit(5000));
    defer reserved.deinit();
    var fixed = Region.fixed(&buffer);
    const r = if (shake.gen.boolean(case.source)) &reserved else &fixed;
    const gpa = t.allocator;
    var model: Model = .{};
    defer model.bytes.deinit(gpa);
    defer model.marks.deinit(gpa);
    var stamp: u8 = 1;
    for (0..96) |_| {
        stamp = if (stamp == 255) 1 else stamp + 1;
        switch (shake.gen.intRange(case.source, u8, 0, 5)) {
            0 => if (model.tail == null) {
                const n = shake.gen.intRange(case.source, usize, 0, 300);
                const at = std.mem.alignForward(usize, model.bytes.items.len, 2);
                if (r.push(u16, n)) |items| {
                    try t.expectEqual(at, @intFromPtr(items.ptr) - @intFromPtr(r.base));
                    @memset(items, @as(u16, stamp) * 0x101);
                    try pad(&model, 2);
                    try model.bytes.appendNTimes(gpa, stamp, n * 2);
                } else |err| {
                    try t.expectEqual(error.LimitExceeded, err);
                    try t.expect(at + n * 2 > r.capacity().raw());
                }
            },
            1 => if (model.tail == null) try model.marks.append(gpa, .{ .mark = r.mark(), .len = model.bytes.items.len }),
            2 => if (model.tail == null) if (model.marks.pop()) |open| {
                r.release(open.mark);
                model.bytes.shrinkRetainingCapacity(open.len);
            },
            3 => if (model.tail) |*items| {
                const value: u32 = @as(u32, stamp) * 0x1010101;
                if (items.append(value)) |_| {
                    try model.bytes.appendNTimes(gpa, stamp, 4);
                } else |err| try t.expectEqual(error.LimitExceeded, err);
            } else if (r.tail(u32)) |opened| {
                model.tail = opened;
                try pad(&model, 4);
                model.tail_start = model.bytes.items.len;
            } else |err| try t.expectEqual(error.LimitExceeded, err),
            4 => if (model.tail) |*items| {
                const sealed = items.seal();
                try t.expectEqual((model.bytes.items.len - model.tail_start) / 4, sealed.len);
                model.tail = null;
            },
            5 => r.trim(),
            else => unreachable,
        }
        try t.expectEqual(model.bytes.items.len, r.used().raw());
        try t.expect(r.committed().raw() >= r.used().raw());
        // Every live byte written is still where it was written; the model's zeros are alignment gaps.
        for (model.bytes.items, r.base[0..model.bytes.items.len]) |expected, actual| {
            if (expected != 0) try t.expectEqual(expected, actual);
        }
    }
}

/// The alignment gap before an item, which the region leaves undefined.
fn pad(model: *Model, alignment: usize) !void {
    const len = model.bytes.items.len;
    try model.bytes.appendNTimes(t.allocator, 0, std.mem.alignForward(usize, len, alignment) - len);
}

test "Region generated traces of pushes, marks, releases, tails and trims agree with a model" {
    try shake.check(t.allocator, {}, trace, .{ .cases = 512, .seed = 0x4e610 });
}
