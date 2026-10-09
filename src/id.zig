//! Distinct ID domains. Import is not authentication or a uniqueness proof.
const std = @import("std");
const scalar = @import("scalar");

/// Copyable scalar identity without arithmetic or cross-tag conversion.
pub fn Id(comptime Tag: type, comptime Repr: type) type {
    return Identity(Tag, Repr, false);
}
/// Zero is rejected at every importing boundary.
pub fn NonZero(comptime Tag: type, comptime Repr: type) type {
    return Identity(Tag, Repr, true);
}
fn Identity(comptime Tag: type, comptime Repr: type, comptime nonzero: bool) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        pub const Domain = Tag;
        pub const FromRawError = error{InvalidId};
        pub const FromBytesError = FromRawError;
        /// Private: use fromRaw/raw.
        _,
        pub inline fn fromRaw(value: Repr) if (nonzero) FromRawError!Self else Self {
            if (nonzero and value == 0) return error.InvalidId;
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
        pub inline fn compare(self: Self, other: Self) std.math.Order {
            return std.math.order(@backingInt(self), @backingInt(other));
        }
        /// Stable Wyhash of canonical little-endian repr, seed zero; not cryptographic.
        pub inline fn hash(self: Self) u64 {
            return std.hash.Wyhash.hash(0, &self.toBytes(.little));
        }
        pub inline fn toBytes(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn fromBytes(data: scalar.Bytes(Repr), endian: std.builtin.Endian) if (nonzero) FromBytesError!Self else Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}
/// Externally serialized nonzero issuer. Init imports the last issued ID (zero for fresh).
pub fn Counter(comptime Tag: type, comptime Repr: type) type {
    scalar.abiInteger(Repr);
    if (@typeInfo(Repr).int.signedness != .unsigned) @compileError("aegis Counter requires an unsigned representation");
    return enum(Repr) {
        const Self = @This();
        /// Private: last successfully issued ID; persists unchanged on exhaustion.
        _,
        pub const NextError = error{IdExhausted};
        pub inline fn init(issued: Repr) Self {
            return @fromBackingInt(issued);
        }
        /// The last ID issued, or null before the first. Reading it changes nothing.
        pub inline fn last(self: Self) ?Id(Tag, Repr) {
            const issued = @backingInt(self);
            return if (issued == 0) null else Id(Tag, Repr).fromRaw(issued);
        }
        pub inline fn next(self: *Self) NextError!Id(Tag, Repr) {
            const sum = @addWithOverflow(@backingInt(self.*), 1);
            if (sum[1] != 0) return error.IdExhausted;
            self.* = @fromBackingInt(sum[0]);
            return Id(Tag, Repr).fromRaw(sum[0]);
        }
    };
}
