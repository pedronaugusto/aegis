const std = @import("std");
const shake = @import("shakedown");
const aegis = @import("root.zig");
const flat = aegis.flat;
const Region = aegis.Region;
const t = std.testing;

const Kind = enum(u8) { leaf, branch };
const Shape = union(enum) { none, circle: f32, path: []const [2]i16, label: []const u8 };
const Ref = struct { id: u32, path: []const u8 };
const Node = struct {
    id: u32,
    kind: Kind,
    visible: bool,
    weight: ?u16,
    name: []const u8,
    tags: []const []const u8,
    shape: Shape,
    children: []const Node,
    parent: ?Ref,
    fixed: [3]u8,
    big: u64,
};
const Tree = flat.Flat(Node);

const leaf_a: Node = .{ .id = 2, .kind = .leaf, .visible = false, .weight = null, .name = "a", .tags = &.{}, .shape = .none, .children = &.{}, .parent = .{ .id = 1, .path = "/root" }, .fixed = .{ 7, 8, 9 }, .big = 1 << 40 };
const leaf_b: Node = .{ .id = 3, .kind = .leaf, .visible = true, .weight = 5, .name = "bee", .tags = &.{ "x", "", "yz" }, .shape = .{ .label = "tag" }, .children = &.{}, .parent = null, .fixed = .{ 0, 0, 1 }, .big = 0 };
const sample: Node = .{
    .id = 1,
    .kind = .branch,
    .visible = true,
    .weight = 300,
    .name = "root",
    .tags = &.{ "one", "two" },
    .shape = .{ .path = &.{ .{ 1, -2 }, .{ 3, -4 } } },
    .children = &.{ leaf_a, leaf_b },
    .parent = null,
    .fixed = .{ 1, 2, 3 },
    .big = std.math.maxInt(u64),
};

const limits: flat.Limits = .{ .depth = .init(16), .items = .init(10_000) };

fn written(comptime T: type, value: T, buffer: []align(flat.alignment) u8) ![]align(flat.alignment) u8 {
    const n = try flat.Flat(T).write(value, buffer);
    return buffer[0..n];
}

test "Flat round trip: a value's image reads in place, verifies, and materializes equal" {
    var buffer: [1024]u8 align(flat.alignment) = undefined;
    const image = try written(Node, sample, &buffer);
    try t.expectEqual(try Tree.size(sample), image.len);

    const v = try Tree.verify(.init(image), limits);
    try t.expectEqual(@as(u32, 1), v.get(.id));
    try t.expectEqual(Kind.branch, v.get(.kind));
    try t.expectEqual(@as(?u16, 300), v.get(.weight));
    try t.expectEqualStrings("root", v.get(.name));
    try t.expectEqual(@as(usize, 2), v.get(.tags).len());
    try t.expectEqualStrings("two", v.get(.tags).at(1));
    try t.expectEqual(std.meta.Tag(Shape).path, v.get(.shape).tag());
    try t.expectEqual(@as(i16, -4), v.get(.shape).get(.path).at(1)[1]);
    try t.expectEqual(@as(usize, 2), v.get(.children).len());
    const b = v.get(.children).at(1);
    try t.expectEqualStrings("bee", b.get(.name));
    try t.expectEqualStrings("tag", b.get(.shape).get(.label));
    try t.expect(b.get(.parent) == null);
    try t.expectEqualStrings("/root", v.get(.children).at(0).get(.parent).?.get(.path));
    try t.expectEqual([3]u8{ 1, 2, 3 }, v.get(.fixed));
    try t.expectEqual(@as(u64, std.math.maxInt(u64)), v.get(.big));

    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    try t.expectEqualDeep(sample, try v.materialize(arena.allocator()));
    // A view of an image this program wrote reads the same, unchecked.
    try t.expectEqualStrings("root", Tree.view(image).get(.name));
}

test "Flat image bytes are fixed: little-endian, offsets forward from their own position" {
    const Small = struct { a: u16, s: []const u8, o: ?u32 };
    var buffer: [64]u8 align(flat.alignment) = undefined;
    const image = try written(Small, .{ .a = 0x0102, .s = "hi", .o = 7 }, &buffer);
    // a at 0; s's offset at 4 (to 16); o's presence at 8 and value at 12; the head ends at 16,
    // then s's count and bytes.
    try t.expectEqualSlices(u8, &.{ 2, 1, 0, 0, 12, 0, 0, 0, 1, 0, 0, 0, 7, 0, 0, 0, 2, 0, 0, 0, 'h', 'i' }, image);
}

test "Flat builder streams the same bytes write lays out" {
    var buffer: [1024]u8 align(flat.alignment) = undefined;
    const expected = try written(Node, sample, &buffer);

    var region = try Region.reserve(.init(1 << 20));
    defer region.deinit();
    var tail = try region.tail(u8);
    var image = try flat.Image.init(&tail, .init(8));
    var root = try Tree.builder(&image);
    try root.set(.id, sample.id);
    try root.set(.kind, sample.kind);
    try root.set(.visible, sample.visible);
    try root.set(.weight, sample.weight);
    var name = try root.begin(.name);
    try name.appendSlice("ro");
    try name.append('o');
    try name.append('t');
    name.end();
    try root.set(.tags, sample.tags);
    try root.set(.shape, sample.shape);
    try root.set(.children, sample.children);
    try root.set(.parent, sample.parent);
    try root.set(.fixed, sample.fixed);
    try root.set(.big, sample.big);
    root.end();
    try t.expectEqualSlices(u8, expected, image.finish());
}

test "Flat refuses what has no stated layout" {
    var buffer: [64]u8 align(flat.alignment) = undefined;
    const Pair = struct { a: u32, s: []const u8 };
    const image = try written(Pair, .{ .a = 1, .s = "abc" }, &buffer);
    // Misaligned input, a zero offset, a count past the end, a depth or item count past the limits.
    try t.expectError(error.Misaligned, flat.Flat(Pair).verify(.init(buffer[1 .. image.len + 1]), limits));
    var broken: [64]u8 align(flat.alignment) = buffer;
    @memset(broken[4..8], 0);
    try t.expectError(error.BadOffset, flat.Flat(Pair).verify(.init(broken[0..image.len]), limits));
    broken = buffer;
    broken[8] = 200;
    try t.expectError(error.Truncated, flat.Flat(Pair).verify(.init(broken[0..image.len]), limits));
    try t.expectError(error.Truncated, flat.Flat(Pair).verify(.init(image[0 .. image.len - 1]), limits));
    try t.expectError(error.LimitExceeded, flat.Flat(Pair).verify(.init(image), .{ .depth = .init(0), .items = .init(100) }));
    try t.expectError(error.LimitExceeded, flat.Flat(Pair).verify(.init(image), .{ .depth = .init(4), .items = .init(3) }));
    // A bool, an enum and an optional's presence hold only their values.
    // Node's head: id at 0, kind at 4, visible at 5, weight's presence at 6.
    var tree: [1024]u8 align(flat.alignment) = undefined;
    const whole = try written(Node, sample, &tree);
    for ([_]usize{ 4, 5, 6 }) |at| {
        const kept = tree[at];
        tree[at] = 9;
        try t.expectError(error.BadValue, Tree.verify(.init(whole), limits));
        tree[at] = kept;
    }
    _ = try Tree.verify(.init(whole), limits);
}

/// An image placed so it ends where the region's committed memory ends, with nothing readable
/// past it: a read beyond a verified image faults instead of passing unseen.
const Guarded = struct {
    region: Region,
    bytes: []align(flat.alignment) u8,

    fn init(len: usize) !Guarded {
        const page = std.heap.pageSize();
        const room = std.mem.alignForward(usize, len, flat.alignment);
        const end = std.mem.alignForward(usize, room, page);
        var region = try Region.reserve(.init(end + page));
        _ = try region.push(u8, end - room);
        const bytes = try region.push(u8, room);
        region.trim();
        return .{ .region = region, .bytes = @alignCast(bytes) };
    }
};

fn walk(bytes: []const u8) !void {
    const v = Tree.verify(.init(bytes), limits) catch return;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    _ = try v.materialize(arena.allocator());
}

test "Flat verify refuses or reads in bounds after every one-byte change" {
    var buffer: [1024]u8 align(flat.alignment) = undefined;
    const image = try written(Node, sample, &buffer);
    var guarded = try Guarded.init(image.len);
    defer guarded.region.deinit();
    const bytes = guarded.bytes[guarded.bytes.len - std.mem.alignForward(usize, image.len, flat.alignment) ..][0..image.len];
    for (0..image.len) |i| {
        for ([_]u8{ 0, 0xff, image[i] ^ 1, image[i] ^ 0x80 }) |changed| {
            @memcpy(bytes, image);
            bytes[i] = changed;
            try walk(bytes);
        }
    }
}

fn fuzzOne(examples: []const []const u8, case: *shake.Case) anyerror!void {
    var guarded = try Guarded.init(512);
    defer guarded.region.deinit();
    const bytes = if (shake.gen.boolean(case.source)) shake.gen.mutated(case.source, guarded.bytes, examples) else shake.gen.bytesInto(case.source, guarded.bytes);
    try walk(bytes);
}

test "Flat verify on generated and mutated images never reads out of bounds" {
    var buffer: [1024]u8 align(flat.alignment) = undefined;
    const image = try written(Node, sample, &buffer);
    const examples = [_][]const u8{image};
    try shake.check(t.allocator, @as([]const []const u8, &examples), fuzzOne, .{ .cases = 512, .seed = 0xf1a7 });
}

test "Flat builder rewrites an element already appended" {
    var region = try Region.reserve(.init(1 << 16));
    defer region.deinit();
    var tail = try region.tail(u8);
    var image = try flat.Image.init(&tail, .init(4));
    const Words = flat.Flat(struct { words: []const u64 });
    var root = try Words.builder(&image);
    var words = try root.begin(.words);
    try words.append(1);
    try words.append(2);
    try words.append(3);
    words.put(0, 30);
    words.put(2, 10);
    words.end();
    root.end();
    const v = Words.view(image.finish());
    try t.expectEqualSlices(u64, &.{ 30, 2, 10 }, v.get(.words));
}
