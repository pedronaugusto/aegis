//! A byte position in a region, as wide as the caller chooses: dense where a pointer is eight
//! bytes, and valid wherever the region is mapped, since it names no address.
const std = @import("std");
const Region = @import("../Region.zig");

pub fn Offset(comptime Tag: type, comptime Repr: type) type {
    if (@typeInfo(Repr) != .int or @typeInfo(Repr).int.signedness != .unsigned or @bitSizeOf(Repr) == 0)
        @compileError("Offset requires a nonzero unsigned integer");
    return enum(Repr) {
        _,
        const Self = @This();
        pub const Domain = Tag;
        pub const OffsetError = error{OutOfBounds};
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        /// Where `item` lies in `region`'s live memory. An item outside it, or past the width, is
        /// an error in every build.
        pub inline fn of(region: *const Region, item: anytype) OffsetError!Self {
            const at = @intFromPtr(item) -% @intFromPtr(region.base); // safe: compared against the region's live extent only
            if (at >= region.top - @intFromPtr(region.base)) return error.OutOfBounds;
            return @fromBackingInt(std.math.cast(Repr, at) orelse return error.OutOfBounds);
        }
        /// The `T` at this offset of `region`: inside its live memory and aligned, checked in
        /// every build.
        pub inline fn get(self: Self, region: *const Region, comptime T: type) OffsetError!*T {
            const at = std.math.cast(usize, @backingInt(self)) orelse return error.OutOfBounds;
            const live = region.top - @intFromPtr(region.base);
            if (at > live or @sizeOf(T) > live - at) return error.OutOfBounds;
            const address = @intFromPtr(region.base) + at;
            if (address % @alignOf(T) != 0) return error.OutOfBounds;
            return @ptrFromInt(address); // safe: checked above: inside the live memory, aligned for T
        }
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
    };
}
