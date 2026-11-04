//! Paired exports: hand-written reads of flat records' bytes, and the same through `Flat`.
//! The record: `id` at 0, `size` at 8, `name`'s offset at 16, a 24-byte head; the name's count
//! and bytes where the offset points. `verify` has no pair here: its checks match a hand-written
//! verifier's one for one, but LLVM merges and schedules them differently with either shape, so
//! its cost is measured in the benchmark pass against FlatBuffers' verifier instead.
const std = @import("std");
const a = @import("aegis");

const Record = struct { id: u32, size: u64, name: []const u8 };
const Records = a.flat.Flat(Record);
/// A record nested in another: `inner`'s offset at 0, `count` at 4, an 8-byte head.
const Outer = struct { inner: Record, count: u32 };
const Outers = a.flat.Flat(Outer);

fn int(comptime I: type, at: [*]const u8) I {
    return std.mem.readInt(I, at[0..@sizeOf(I)], .little);
}

/// The size plus the name's length, read in place.
export fn baselineFlatGet(image: [*]align(16) const u8) u64 {
    const size = int(u64, image + 8);
    const name = image + 16 + int(u32, image + 16);
    return size + int(u32, name);
}
export fn wrapperFlatGet(image: [*]align(16) const u8) u64 {
    const v = Records.view(image[0..24]);
    return v.get(.size) + v.get(.name).len;
}

/// A nested record's size plus the outer count: one relative add to reach the inner head.
export fn baselineFlatNested(image: [*]align(16) const u8) u64 {
    const inner = image + int(u32, image);
    return int(u64, inner + 8) + int(u32, image + 4);
}
export fn wrapperFlatNested(image: [*]align(16) const u8) u64 {
    const v = Outers.view(image[0..8]);
    return v.get(.inner).get(.size) + v.get(.count);
}
