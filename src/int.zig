//! Scalar integers with arithmetic checks in every build mode.
const std = @import("std");
const scalar = @import("scalar.zig");

/// Failed integer sign/width conversion. Floating point is deliberately excluded.
pub const CastError = error{Overflow};

/// `Value` when every `Source` converts to `Target` on every supported target, else `CastError!Value`: a conversion
/// that cannot fail carries no error set. `usize` and `isize` count as the narrowest and widest they are anywhere, so
/// `u32` to `usize` and `usize` to `u64` cannot fail and `u64` to `usize` can, on every target alike.
pub fn Lifted(comptime Source: type, comptime Target: type, comptime Value: type) type {
    return if (scalar.lossless(Source, Target)) Value else CastError!Value;
}

fn CastResult(comptime Target: type, comptime Source: type) type {
    return switch (@typeInfo(Source)) {
        .int => Lifted(Source, Target, Target),
        .comptime_int => CastError!Target,
        else => @compileError("aegis integer cast requires an integer source"),
    };
}

pub inline fn cast(comptime Target: type, source: anytype) CastResult(Target, @TypeOf(source)) {
    scalar.integer(Target);
    switch (@typeInfo(@TypeOf(source))) {
        .int => {
            const Source = @TypeOf(source);
            // Every value fits: a plain widening, with no range check and no error.
            if (comptime scalar.lossless(Source, Target)) return @intCast(source); // safe: every source value fits the target
            if (comptime std.math.maxInt(Source) > std.math.maxInt(Target)) {
                if (source > std.math.maxInt(Target)) return error.Overflow;
            }
            if (comptime std.math.minInt(Source) < std.math.minInt(Target)) {
                if (source < std.math.minInt(Target)) return error.Overflow;
            }
            return @intCast(source); // safe: both relevant target bounds checked above
        },
        .comptime_int => {
            if (source < std.math.minInt(Target) or source > std.math.maxInt(Target)) return error.Overflow;
            return source;
        },
        else => unreachable, // unreachable: `CastResult` rejects every other source
    }
}

/// Checked arithmetic; operands are raw Repr, results remain checked.
pub fn Checked(comptime Repr: type) type {
    scalar.integer(Repr);
    return struct {
        const Self = @This();
        /// Private: use init/raw; Zig reflection can bypass this contract.
        value: Repr,
        pub const AddError = error{ Overflow, Underflow };
        pub const SubError = error{ Overflow, Underflow };
        pub const MulError = error{ Overflow, Underflow };
        pub const DivError = error{ DivisionByZero, Overflow };
        pub const RemError = error{DivisionByZero};
        pub const ShlError = error{ InvalidShift, Overflow, Underflow };
        pub inline fn init(value: Repr) Self {
            return .{ .value = value };
        }
        pub inline fn raw(self: Self) Repr {
            return self.value;
        }
        pub inline fn add(self: Self, rhs: Repr) AddError!Self {
            const result = @addWithOverflow(self.value, rhs);
            if (result[1] != 0) return if (rhs < 0) error.Underflow else error.Overflow;
            return init(result[0]);
        }
        pub inline fn sub(self: Self, rhs: Repr) SubError!Self {
            const result = @subWithOverflow(self.value, rhs);
            if (result[1] != 0) return if (rhs > 0) error.Underflow else error.Overflow;
            return init(result[0]);
        }
        pub inline fn mul(self: Self, rhs: Repr) MulError!Self {
            const result = @mulWithOverflow(self.value, rhs);
            if (result[1] != 0) return if ((self.value < 0) != (rhs < 0)) error.Underflow else error.Overflow;
            return init(result[0]);
        }
        pub inline fn div(self: Self, rhs: Repr) DivError!Self {
            if (rhs == 0) return error.DivisionByZero;
            if (comptime @typeInfo(Repr).int.signedness == .signed) {
                if (self.value == std.math.minInt(Repr) and rhs == -1) return error.Overflow;
            }
            return init(@divTrunc(self.value, rhs));
        }
        pub inline fn rem(self: Self, rhs: Repr) RemError!Self {
            if (rhs == 0) return error.DivisionByZero;
            if (comptime @typeInfo(Repr).int.signedness == .signed) {
                if (rhs == -1) return init(0); // min/-1 remainder is mathematically zero
            }
            return init(@rem(self.value, rhs));
        }
        pub inline fn shl(self: Self, amount: anytype) ShlError!Self {
            const n = std.math.cast(usize, amount) orelse return error.InvalidShift;
            if (n >= @bitSizeOf(Repr)) return error.InvalidShift;
            const shift: std.math.Log2Int(Repr) = @intCast(n); // safe: validated representation width
            const wide = @Int(@typeInfo(Repr).int.signedness, @bitSizeOf(Repr) * 2);
            const result = @as(wide, self.value) << shift;
            if (result > std.math.maxInt(Repr)) return error.Overflow;
            if (result < std.math.minInt(Repr)) return error.Underflow;
            return init(@intCast(result)); // safe: exact wider shift checked against both repr bounds
        }

        pub inline fn toBytes(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, self.value, endian);
        }
        pub inline fn fromBytes(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return init(scalar.decode(Repr, data, endian));
        }
    };
}

/// Explicit clamping policy, never an implicit promotion from Checked.
pub fn Saturating(comptime Repr: type) type {
    scalar.integer(Repr);
    return struct {
        const Self = @This();
        /// Private: use init/raw.
        value: Repr,
        pub const DivError = error{DivisionByZero};
        pub const RemError = error{DivisionByZero};
        pub const ShlError = error{InvalidShift};
        pub inline fn init(value: Repr) Self {
            return .{ .value = value };
        }
        pub inline fn raw(self: Self) Repr {
            return self.value;
        }
        pub inline fn add(self: Self, rhs: Repr) Self {
            return init(self.value +| rhs);
        }
        pub inline fn sub(self: Self, rhs: Repr) Self {
            return init(self.value -| rhs);
        }
        pub inline fn mul(self: Self, rhs: Repr) Self {
            return init(self.value *| rhs);
        }
        pub inline fn div(self: Self, rhs: Repr) DivError!Self {
            if (rhs == 0) return error.DivisionByZero;
            if (comptime @typeInfo(Repr).int.signedness == .signed) {
                if (self.value == std.math.minInt(Repr) and rhs == -1) return init(std.math.maxInt(Repr));
            }
            return init(@divTrunc(self.value, rhs));
        }
        pub inline fn rem(self: Self, rhs: Repr) RemError!Self {
            return init((try Checked(Repr).init(self.value).rem(rhs)).raw());
        }
        pub inline fn shl(self: Self, amount: anytype) ShlError!Self {
            const checked = Checked(Repr).init(self.value).shl(amount) catch |err| switch (err) {
                error.InvalidShift => return error.InvalidShift,
                error.Overflow => return init(std.math.maxInt(Repr)),
                error.Underflow => return init(std.math.minInt(Repr)),
            };
            return init(checked.raw());
        }

        pub inline fn toBytes(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, self.value, endian);
        }
        pub inline fn fromBytes(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return init(scalar.decode(Repr, data, endian));
        }
    };
}

/// Inclusive compile-time bounds; operations validate representation overflow before range.
pub fn Ranged(comptime Repr: type, comptime min: Repr, comptime max: Repr) type {
    scalar.abiInteger(Repr);
    if (min > max) @compileError("aegis ranged integer requires min <= max");
    return enum(Repr) {
        const Self = @This();
        /// Private: use init/raw; foreign construction must validate again.
        _,
        pub const InitError = error{OutOfRange};
        pub const AddError = Checked(Repr).AddError || InitError;
        pub const SubError = Checked(Repr).SubError || InitError;
        pub const MulError = Checked(Repr).MulError || InitError;
        pub const DivError = Checked(Repr).DivError || InitError;
        pub const RemError = Checked(Repr).RemError || InitError;
        pub const ShlError = Checked(Repr).ShlError || InitError;
        pub fn init(value: Repr) InitError!Self {
            if (value < min or value > max) return error.OutOfRange;
            return @fromBackingInt(value);
        }
        pub fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub fn add(self: Self, rhs: Repr) AddError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).add(rhs)).raw());
        }
        pub fn sub(self: Self, rhs: Repr) SubError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).sub(rhs)).raw());
        }
        pub fn mul(self: Self, rhs: Repr) MulError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).mul(rhs)).raw());
        }
        pub fn div(self: Self, rhs: Repr) DivError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).div(rhs)).raw());
        }
        pub fn rem(self: Self, rhs: Repr) RemError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).rem(rhs)).raw());
        }
        pub fn shl(self: Self, amount: anytype) ShlError!Self {
            return init((try Checked(Repr).init(@backingInt(self)).shl(amount)).raw());
        }
        pub fn toBytes(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub fn fromBytes(data: scalar.Bytes(Repr), endian: std.builtin.Endian) InitError!Self {
            return init(scalar.decode(Repr, data, endian));
        }
    };
}
