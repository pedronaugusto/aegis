//! Memory read as another type, where the language checks nothing of the view: glint's P007
//! seam for it (glint.json), and nothing else lives here. Each function asserts what makes its
//! view hold: `alignedItems` and `grown` in Debug, where the safe builds keep the language's own
//! checks of the slices and the `@alignCast` they stand for, the others in every build.
const std = @import("std");
const builtin = @import("builtin");
const assert = @import("assert.zig");

/// Whether `alignedItems` and `grown` assert what they are handed.
const checked = builtin.optimize == .debug;

/// `bytes` as `n` items of `T`: `bytes` is exactly `n` of `T`'s size and starts aligned for `T`.
pub inline fn items(comptime T: type, bytes: []u8, n: usize) []T {
    return alignedItems(T, @alignOf(T), bytes, n);
}

/// `bytes` as `n` items of `T` at alignment `alignment`, at least `T`'s: `bytes` is exactly `n` of
/// `T`'s size and starts so aligned. A type of no size takes no bytes, and its `n` items are at
/// the alignment.
///
/// Its length is asserted in Debug and its alignment is `@alignCast`'s check in the safe builds,
/// so a region's push, a pool's growth and a plan's parts compile in ReleaseSafe and ReleaseFast to
/// the code a hand-written owner does (the parity contracts hold them to it).
pub inline fn alignedItems(comptime T: type, comptime alignment: usize, bytes: []u8, n: usize) []align(alignment) T {
    comptime std.debug.assert(alignment >= @alignOf(T));
    if (comptime @sizeOf(T) == 0) {
        if (checked) assert.invariant(bytes.len == 0, "items of no size take no bytes");
        const none: [*]align(alignment) T = @ptrFromInt(alignment); // safe: a type of no size is never read; any aligned address names its items
        return none[0..n];
    }
    if (checked) assert.invariant(bytes.len / @sizeOf(T) == n and bytes.len % @sizeOf(T) == 0, "a view of items is exactly their bytes");
    // The bytes' own address at every length: `std.mem.bytesAsSlice` answers a global empty
    // array for no bytes, which would move a region's empty push off the region. Its alignment
    // is `@alignCast`'s own check.
    const first: [*]align(alignment) T = @ptrCast(@alignCast(bytes.ptr)); // safe: the length asserted above, the alignment checked by @alignCast
    return first[0..n];
}

/// `from` grown in place to `total` items: the bytes past them up to `total` are the caller's,
/// laid out for `T` (a region's `extend` asserted they follow at its top, its commit committed
/// them). Never shrinks, which it asserts in Debug.
pub inline fn grown(comptime T: type, from: []T, total: usize) []T {
    if (checked) assert.invariant(total >= from.len, "a view grows, never shrinks");
    return from.ptr[0..total]; // safe: the caller holds the bytes past `from`, as above
}

/// `from`, a slice of a type laid out as `To` (its size and alignment, which the compiler
/// checks), read as `To`: the same memory, read only.
pub inline fn sameLayout(comptime To: type, from: anytype) []const To {
    const From = @typeInfo(@TypeOf(from)).pointer.child;
    comptime std.debug.assert(@sizeOf(From) == @sizeOf(To));
    comptime std.debug.assert(@alignOf(From) == @alignOf(To));
    return @ptrCast(from); // safe: the same size and alignment, checked above
}

/// The `T` that `context` was made from, where an interface carries its implementation as an
/// opaque pointer (`std.mem.Allocator`'s `ptr`): `context` is a `*T` its maker passed.
pub inline fn context(comptime T: type, pointer: *anyopaque) *T {
    assert.invariant(@intFromPtr(pointer) % @alignOf(T) == 0, "an interface's context is the implementation it was made from");
    return @ptrCast(@alignCast(pointer)); // safe: asserted aligned; made from a *T
}
