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
        /// Whether both name the same position of the same domain.
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
        /// The order of the positions, as the order of the raw values.
        pub inline fn compare(self: Self, other: Self) std.math.Order {
            return std.math.order(@backingInt(self), @backingInt(other));
        }
        pub inline fn get(self: Self, slice: anytype) IndexError!@TypeOf(&slice[0]) {
            const i = std.math.cast(usize, self.raw()) orelse return error.OutOfBounds;
            if (i >= slice.len) return error.OutOfBounds;
            return &slice[i];
        }
    };
}

/// A position of `Index(Tag, Repr)` or none, in the same width: biased by one, so none is zero.
pub fn OptionalIndex(comptime Tag: type, comptime Repr: type) type {
    return enum(Repr) {
        none = 0,
        _,
        const Self = @This();
        /// A position at the type's largest value has no room for the bias, and stops in every build.
        pub inline fn some(position: Index(Tag, Repr)) Self {
            if (position.raw() == std.math.maxInt(Repr)) @panic("index past its optional's range");
            return @fromBackingInt(position.raw() + 1);
        }
        pub inline fn unwrap(self: Self) ?Index(Tag, Repr) {
            if (self == .none) return null;
            return @fromBackingInt(@backingInt(self) - 1);
        }
    };
}
