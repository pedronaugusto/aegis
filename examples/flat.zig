//! A record saved as one flat image and loaded back: written at its exact size, its bytes taken
//! as untrusted and checked once, then read in place with no copy; a parser with no value to
//! write streams the same image part by part into a region's tail.
const std = @import("std");
const aegis = @import("aegis");

const flat = aegis.flat;
const Entry = struct { id: u32, name: []const u8, tags: []const []const u8, size: ?u64 };
const Entries = flat.Flat(Entry);
const limits: flat.Limits = .{ .depth = .init(8), .items = .init(1024) };

pub fn main() !void {
    const entry: Entry = .{ .id = 7, .name = "relic", .tags = &.{ "vcs", "zig" }, .size = 4096 };

    // Written at its exact size, measured first; the image has no pointers, so saving it is one write.
    var buffer: [256]u8 align(flat.alignment) = undefined;
    const n = try Entries.write(entry, &buffer);
    aegis.assert.invariant(n == try Entries.size(entry), "the exact size");

    // Loaded bytes are untrusted: verify checks every offset, count and value before a view exists.
    const v = try Entries.verify(.init(buffer[0..n]), limits);
    aegis.assert.invariant(v.get(.id) == 7, "a scalar read in place");
    aegis.assert.invariant(std.mem.eql(u8, v.get(.name), "relic"), "a string is a slice of the image");
    aegis.assert.invariant(std.mem.eql(u8, v.get(.tags).at(1), "zig"), "a nested slice reads by index");
    aegis.assert.invariant(v.get(.size).? == 4096, "an optional reads as one");

    // A broken image is refused, never read out of bounds.
    var broken: [256]u8 align(flat.alignment) = buffer;
    broken[4] = 0xfc;
    if (Entries.verify(.init(broken[0..n]), limits)) |_| unreachable else |err| aegis.assert.invariant(err == error.Truncated, "an offset past the end");

    // A parser streams the image into a region's tail; the result is the same bytes.
    var r = try aegis.Region.reserve(.init(1 << 20));
    defer r.deinit();
    var tail = try r.tail(u8);
    var image = try flat.Image.init(&tail, limits.depth);
    var root = try Entries.builder(&image);
    try root.set(.id, 7);
    var name = try root.begin(.name);
    try name.appendSlice("relic");
    name.end();
    try root.set(.tags, entry.tags);
    try root.set(.size, 4096);
    root.end();
    aegis.assert.invariant(std.mem.eql(u8, image.finish(), buffer[0..n]), "streamed as written");
}
