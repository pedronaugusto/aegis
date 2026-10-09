//! Explicit moves into disjoint uninitialized storage; no hidden cleanup.
const std = @import("std");
pub fn move(comptime T: type, source: *T, destination: *T) void {
    if (comptime switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "moveInto"),
        else => false,
    }) {
        source.moveInto(destination);
    } else {
        destination.* = source.*;
        source.* = undefined;
    }
}
pub fn overlaps(comptime T: type, value: *const T, storage: anytype) bool {
    if (@sizeOf(T) == 0 or storage.len == 0) return false;
    const a = @intFromPtr(value); // safe: live address compared only for overlap
    const b = @intFromPtr(storage.ptr); // safe: live storage address
    const bytes = std.math.mul(usize, storage.len, @sizeOf(@typeInfo(@TypeOf(storage)).pointer.child)) catch return true;
    return if (a >= b) a - b < bytes else b - a < @sizeOf(T);
}
