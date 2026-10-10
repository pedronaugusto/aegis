//! Whether a value and the storage it is moved into overlap; no hidden cleanup.
const std = @import("std");
pub inline fn overlaps(comptime T: type, value: *const T, storage: anytype) bool {
    if (@sizeOf(T) == 0 or storage.len == 0) return false;
    const a = @intFromPtr(value); // safe: live address compared only for overlap
    const b = @intFromPtr(storage.ptr); // safe: live storage address
    const bytes = std.math.mul(usize, storage.len, @sizeOf(@typeInfo(@TypeOf(storage)).pointer.child)) catch return true;
    return if (a >= b) a - b < bytes else b - a < @sizeOf(T);
}

pub inline fn overlapsOwner(comptime T: type, value: *const T, owner: anytype) bool {
    return overlaps(T, value, @as([]const u8, std.mem.asBytes(owner)));
}
