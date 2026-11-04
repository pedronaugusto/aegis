//! Flat's every read, check and write, compiled for the big-endian profiles: there an image's
//! little-endian numbers are swapped in the accessors, and a slice of numbers wider than a byte
//! reads through a view instead of in place.
const std = @import("std");
const a = @import("aegis");

const Kind = enum(u8) { leaf, branch };
const Shape = union(enum) { none, circle: f32, path: []const [2]i16, label: []const u8 };
const Node = struct {
    id: u32,
    kind: Kind,
    weight: ?u16,
    name: []const u8,
    values: []const u32,
    shape: Shape,
    children: []const Node,
    big: u64,
};
const Nodes = a.flat.Flat(Node);
const limits: a.flat.Limits = .{ .depth = .init(8), .items = .init(1 << 16) };

/// A slice read in place, or a view of one, by its length.
fn count(slice: anytype) usize {
    return if (@typeInfo(@TypeOf(slice)) == .pointer) slice.len else slice.len();
}
fn item(slice: anytype, i: usize) @TypeOf(if (@typeInfo(@TypeOf(slice)) == .pointer) slice[0] else slice.at(0)) {
    return if (@typeInfo(@TypeOf(slice)) == .pointer) slice[i] else slice.at(i);
}

/// Every read of a verified image, summed.
export fn flatProfileRead(bytes: [*]const u8, len: usize) u64 {
    const v = Nodes.verify(.init(bytes[0..len]), limits) catch return 0;
    var sum: u64 = v.get(.id) +% v.get(.big) +% @backingInt(v.get(.kind)) +% (v.get(.weight) orelse 0) +% v.get(.name).len;
    const values = v.get(.values);
    for (0..count(values)) |i| sum +%= item(values, i);
    const shape = v.get(.shape);
    switch (shape.tag()) {
        .none => {},
        .circle => sum +%= @intFromFloat(shape.get(.circle)),
        .path => sum +%= @bitCast(@as(i64, shape.get(.path).at(0)[1])),
        .label => sum +%= shape.get(.label).len,
    }
    const children = v.get(.children);
    for (0..children.len()) |i| sum +%= children.at(i).get(.id);
    return sum;
}

/// A verified image made a plain value again, in `buffer`.
export fn flatProfileMaterialize(bytes: [*]const u8, len: usize, buffer: [*]u8, room: usize) u64 {
    const v = Nodes.verify(.init(bytes[0..len]), limits) catch return 0;
    var fixed: std.heap.FixedBufferAllocator = .init(buffer[0..room]);
    const node = v.materialize(fixed.allocator()) catch return 0;
    return node.values.len +% node.children.len;
}

/// A value written whole, and the same value streamed into a region's tail.
export fn flatProfileWrite(out: [*]align(a.flat.alignment) u8, room: usize, id: u32) usize {
    const leaf: Node = .{ .id = id + 1, .kind = .leaf, .weight = null, .name = "b", .values = &.{}, .shape = .none, .children = &.{}, .big = 0 };
    const node: Node = .{ .id = id, .kind = .branch, .weight = 3, .name = "a", .values = &.{ 1, 2 }, .shape = .{ .path = &.{.{ 1, -1 }} }, .children = &.{leaf}, .big = 1 << 40 };
    const n = Nodes.size(node) catch return 0;
    if (n > room) return 0;
    _ = Nodes.write(node, out[0..room]) catch return 0;

    var r = a.Region.reserve(.init(1 << 16)) catch return 0;
    defer r.deinit();
    var tail = r.tail(u8) catch return 0;
    var image = a.flat.Image.init(&tail, limits.depth) catch return 0;
    var root = Nodes.builder(&image) catch return 0;
    stream(&root, node) catch return 0;
    return if (std.mem.eql(u8, image.finish(), out[0..n])) n else 0;
}
fn stream(root: *Nodes.Builder, node: Node) a.flat.Error!void {
    try root.set(.id, node.id);
    try root.set(.kind, node.kind);
    try root.set(.weight, node.weight);
    try root.set(.name, node.name);
    var values = try root.begin(.values);
    try values.appendSlice(node.values);
    values.end();
    try root.set(.shape, node.shape);
    try root.set(.children, node.children);
    try root.set(.big, node.big);
    root.end();
}
