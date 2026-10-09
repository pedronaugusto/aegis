//! Position branding, never liveness or pointer stability.
const std = @import("std");
pub fn Index(comptime Tag: type, comptime Repr: type) type {
    if (@typeInfo(Repr) != .int or @typeInfo(Repr).int.signedness != .unsigned or @bitSizeOf(Repr) == 0)
        @compileError("Index requires a nonzero unsigned integer");
    return enum(Repr) {
        _,
        const Self = @This();
        pub const Domain = Tag;
        pub const IndexError = error{OutOfBounds};
        pub inline fn from(value: Repr, len: usize) IndexError!Self {
            if (value >= len) return error.OutOfBounds;
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn get(self: Self, slice: anytype) IndexError!@TypeOf(&slice[0]) {
            const i = std.math.cast(usize, self.raw()) orelse return error.OutOfBounds;
            if (i >= slice.len) return error.OutOfBounds;
            return &slice[i];
        }
    };
}
