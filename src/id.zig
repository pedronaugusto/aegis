//! Distinct ID domains. Import is not authentication or a uniqueness proof.
const std = @import("std");
const scalar = @import("scalar.zig");
const units = @import("units.zig");

/// Copyable scalar identity without arithmetic or cross-tag conversion.
pub fn Id(comptime Tag: type, comptime Repr: type) type {
    return Identity(Tag, Repr, false);
}
/// Zero is rejected at every importing boundary.
pub fn NonZero(comptime Tag: type, comptime Repr: type) type {
    return Identity(Tag, Repr, true);
}
/// The counts an id domain's relations speak in: `Tag.Step` when the tag declares one (a `units.Count` of
/// the id's representation, so ids and the things they number stay apart), else a count of the domain's own ids.
fn StepOf(comptime Tag: type, comptime Repr: type) type {
    const declared = switch (@typeInfo(Tag)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(Tag, "Step"),
        else => false,
    };
    if (!declared) return units.Count(Tag, Repr);
    const Step = Tag.Step;
    if (@typeInfo(Step) != .@"enum" or !@hasDecl(Step, "Domain") or Step != units.Count(Step.Domain, Repr))
        @compileError("an id domain's Step must be a units.Count of the id's representation");
    return Step;
}
fn unsignedRelations(comptime Repr: type) void {
    if (@typeInfo(Repr).int.signedness != .unsigned) @compileError("id relations require an unsigned representation");
}
fn Identity(comptime Tag: type, comptime Repr: type, comptime nonzero: bool) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        pub const Domain = Tag;
        /// The count type of `advance`, `retreat` and `distanceTo`.
        pub const Step = StepOf(Tag, Repr);
        pub const FromRawError = error{InvalidId};
        pub const FromBytesError = FromRawError;
        /// Moving on past the largest representable id.
        pub const AdvanceError = error{IdExhausted};
        /// Moving back past the smallest valid id: zero, or for `NonZero`, one.
        pub const RetreatError = error{IdUnderflow};
        pub const DistanceError = error{Backwards};
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
        /// The next id. `error.IdExhausted` past the largest, never a wrap.
        pub inline fn successor(self: Self) AdvanceError!Self {
            comptime unsignedRelations(Repr);
            const sum = @addWithOverflow(@backingInt(self), 1);
            if (sum[1] != 0) return error.IdExhausted;
            return @fromBackingInt(sum[0]);
        }
        /// The id before this one. `error.IdUnderflow` before the first valid id, never a wrap.
        pub inline fn predecessor(self: Self) RetreatError!Self {
            comptime unsignedRelations(Repr);
            const below = @subWithOverflow(@backingInt(self), 1);
            if (below[1] != 0 or (nonzero and below[0] == 0)) return error.IdUnderflow;
            return @fromBackingInt(below[0]);
        }
        /// This id moved on by `by` steps. `error.IdExhausted` past the largest, never a wrap.
        pub inline fn advance(self: Self, by: Step) AdvanceError!Self {
            comptime unsignedRelations(Repr);
            const sum = @addWithOverflow(@backingInt(self), by.raw());
            if (sum[1] != 0) return error.IdExhausted;
            return @fromBackingInt(sum[0]);
        }
        /// This id moved back by `by` steps. `error.IdUnderflow` before the first valid id, never a wrap.
        pub inline fn retreat(self: Self, by: Step) RetreatError!Self {
            comptime unsignedRelations(Repr);
            const below = @subWithOverflow(@backingInt(self), by.raw());
            if (below[1] != 0 or (nonzero and below[0] == 0)) return error.IdUnderflow;
            return @fromBackingInt(below[0]);
        }
        /// How many steps lead from this id on to `other`; zero for the same id, `error.Backwards` when
        /// `other` is the earlier one.
        pub inline fn distanceTo(self: Self, other: Self) DistanceError!Step {
            comptime unsignedRelations(Repr);
            if (@backingInt(other) < @backingInt(self)) return error.Backwards;
            return Step.fromRaw(@backingInt(other) - @backingInt(self));
        }
        /// Stable Wyhash of canonical little-endian repr, seed zero; not cryptographic.
        pub inline fn hash(self: Self) u64 {
            return std.hash.Wyhash.hash(0, &self.toBytes(.little));
        }
        pub inline fn toBytes(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn fromBytes(data: scalar.Bytes(Repr), endian: std.lang.Endian) if (nonzero) FromBytesError!Self else Self {
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
