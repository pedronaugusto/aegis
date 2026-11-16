//! Reads of a flat image in place: glint's P007 seam for them (glint.json), and nothing else
//! lives here. A view is one pointer into an image, as a hand-written reader's is, so a read
//! carries no length to check: each primitive's precondition is that its position, and the bytes
//! it reads there, lie inside an image that `Flat(T).verify` checked or a `Flat` builder wrote,
//! which every caller in `flat.zig` holds by reaching the position through the image's own
//! offsets. What can be asserted without a length is.
const std = @import("std");
const assert = @import("../assert.zig");

/// A position in an image.
pub const At = [*]const u8;

/// The position `offset` bytes past `at`.
pub inline fn past(at: At, offset: usize) At {
    return at + offset;
}

/// The little-endian `I` at `at`.
pub inline fn int(comptime I: type, at: At) I {
    return std.mem.readInt(I, at[0..@sizeOf(I)], .little);
}

/// The `n` elements of `E` at `at`, in place: `at` is aligned for `E`, which a verified or
/// written image keeps.
pub inline fn elements(comptime E: type, at: At, n: usize) []const E {
    assert.invariant(@intFromPtr(at) % @alignOf(E) == 0, "a flat image's elements lie aligned");
    const items: [*]const E = @ptrCast(@alignCast(at)); // safe: asserted aligned; inside the image
    return items[0..n];
}

/// `bytes`, an image that starts at `alignment`, as aligned bytes.
pub inline fn aligned(comptime alignment: usize, bytes: []const u8) []align(alignment) const u8 {
    assert.invariant(@intFromPtr(bytes.ptr) % alignment == 0, "a flat image starts aligned");
    return @alignCast(bytes); // safe: asserted above
}
