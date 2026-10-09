//! Scalar units with explicit, checked conversion; no scheduler or implicit clock cast.
const std = @import("std");
const ints = @import("int");
const scalar = @import("scalar");
/// Rounding down/up is toward negative/positive infinity, respectively.
pub const Rounding = enum { exact, down, up };
/// Fixed duration scales, represented exactly as nanoseconds.
pub const Unit = enum {
    nanosecond,
    microsecond,
    millisecond,
    second,
    minute,
    hour,
    day,
    pub fn nanoseconds(self: Unit) u64 {
        return switch (self) {
            .nanosecond => 1,
            .microsecond => 1_000,
            .millisecond => 1_000_000,
            .second => 1_000_000_000,
            .minute => 60_000_000_000,
            .hour => 3_600_000_000_000,
            .day => 86_400_000_000_000,
        };
    }
};
const ScaleError = error{ Overflow, Inexact };

// Wide exact intermediate avoids falsely rejecting a representable quotient.
// Every accepted scale is u64; input bits + 65 includes product and sign.
inline fn scaled(comptime Target: type, comptime numerator: u64, comptime denominator: u64, value: anytype, rounding: Rounding) ScaleError!Target {
    scalar.integer(Target);
    const Source = @TypeOf(value);
    scalar.integer(Source);
    if (comptime @typeInfo(Target).int.signedness == .unsigned) {
        if (value < 0) return error.Overflow;
    }
    const gcd = comptime std.math.gcd(numerator, denominator);
    const n = numerator / gcd;
    const d = denominator / gcd;
    if (comptime d == 1 and n <= std.math.maxInt(Target)) {
        const input = try ints.cast(Target, value);
        const product = @mulWithOverflow(input, @as(Target, n));
        if (product[1] != 0) return error.Overflow;
        return product[0];
    }

    if (comptime n == 1 and d <= std.math.maxInt(Source)) {
        const divisor: Source = d;
        const quotient = @divFloor(value, divisor);
        const remainder = @mod(value, divisor);
        const result = switch (rounding) {
            .exact => if (remainder == 0) quotient else return error.Inexact,
            .down => quotient,
            .up => quotient + @intFromBool(remainder != 0), // remainder implies divisor > 1, so quotient has room
        };
        return ints.cast(Target, result);
    }

    const wide = @Int(.signed, @bitSizeOf(Source) + 65);
    const product = @as(wide, value) * n;
    const remainder = @mod(product, d);
    const result = switch (rounding) {
        .exact => if (remainder == 0) @divTrunc(product, d) else return error.Inexact,
        .down => @divFloor(product, d),
        .up => @divFloor(product, d) + @intFromBool(remainder != 0),
    };
    return ints.cast(Target, result);
}

/// Count domains are distinct; multiplying by a scalar retains that domain.
pub fn Count(comptime Tag: type, comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        pub const Domain = Tag;
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const MulError = ints.Checked(Repr).MulError;
        pub const ConvertError = ints.CastError;
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn add(self: Self, rhs: Self) AddError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).add(@backingInt(rhs))).raw());
        }
        pub inline fn sub(self: Self, rhs: Self) SubError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).sub(@backingInt(rhs))).raw());
        }
        pub inline fn mul(self: Self, rhs: Repr) MulError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).mul(rhs)).raw());
        }
        pub inline fn convert(self: Self, comptime Target: type) ConvertError!Count(Tag, Target) {
            return Count(Tag, Target).fromRaw(try ints.cast(Target, @backingInt(self)));
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Distinct bytes count, never an implicit unit conversion.
pub fn Bytes(comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const MulError = ints.Checked(Repr).MulError;
        pub const ConvertError = error{ Overflow, Inexact };
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn add(self: Self, rhs: Self) AddError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).add(@backingInt(rhs))).raw());
        }
        pub inline fn sub(self: Self, rhs: Self) SubError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).sub(@backingInt(rhs))).raw());
        }
        pub inline fn mul(self: Self, rhs: Repr) MulError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).mul(rhs)).raw());
        }
        pub inline fn convert(self: Self, comptime Target: type) ConvertError!Bytes(Target) {
            return Bytes(Target).fromRaw(try ints.cast(Target, @backingInt(self)));
        }
        pub const ToBitsError = ConvertError;
        pub inline fn toBits(self: Self) ToBitsError!Bits(Repr) {
            return Bits(Repr).fromRaw(try scaled(Repr, 8, 1, @backingInt(self), .exact));
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Distinct bits count, never an implicit unit conversion.
pub fn Bits(comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const MulError = ints.Checked(Repr).MulError;
        pub const ConvertError = error{ Overflow, Inexact };
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn add(self: Self, rhs: Self) AddError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).add(@backingInt(rhs))).raw());
        }
        pub inline fn sub(self: Self, rhs: Self) SubError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).sub(@backingInt(rhs))).raw());
        }
        pub inline fn mul(self: Self, rhs: Repr) MulError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).mul(rhs)).raw());
        }
        pub inline fn convert(self: Self, comptime Target: type) ConvertError!Bits(Target) {
            return Bits(Target).fromRaw(try ints.cast(Target, @backingInt(self)));
        }
        pub const ToBytesError = ConvertError;
        pub const ToBytesRoundedError = ConvertError;
        pub inline fn toBytes(self: Self) ToBytesError!Bytes(Repr) {
            return Bytes(Repr).fromRaw(try scaled(Repr, 1, 8, @backingInt(self), .exact));
        }
        pub inline fn toBytesRounded(self: Self, rounding: Rounding) ToBytesRoundedError!Bytes(Repr) {
            return Bytes(Repr).fromRaw(try scaled(Repr, 1, 8, @backingInt(self), rounding));
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Signed representations permit negative spans; unsigned conversion rejects negative input.
pub fn Duration(comptime unit: Unit, comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const MulError = ints.Checked(Repr).MulError;
        pub const ConvertError = error{ Overflow, Inexact };
        pub const ToIoDurationError = ConvertError;
        pub const FromIoDurationError = ConvertError;
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn add(self: Self, rhs: Self) AddError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).add(@backingInt(rhs))).raw());
        }
        pub inline fn sub(self: Self, rhs: Self) SubError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).sub(@backingInt(rhs))).raw());
        }
        pub inline fn mul(self: Self, rhs: Repr) MulError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).mul(rhs)).raw());
        }
        pub inline fn convert(self: Self, comptime target: Unit, comptime Target: type, rounding: Rounding) ConvertError!Duration(target, Target) {
            return Duration(target, Target).fromRaw(try scaled(Target, unit.nanoseconds(), target.nanoseconds(), @backingInt(self), rounding));
        }
        pub inline fn toIoDuration(self: Self) ToIoDurationError!std.Io.Duration {
            return .fromNanoseconds(try scaled(i96, unit.nanoseconds(), 1, @backingInt(self), .exact));
        }
        pub inline fn fromIoDuration(value: std.Io.Duration, rounding: Rounding) FromIoDurationError!Self {
            return fromRaw(try scaled(Repr, 1, unit.nanoseconds(), value.nanoseconds, rounding));
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// A point in a caller-owned clock/epoch. No instant+instant or numerical clock cast.
/// Use .real/.awake/.boot (std.Io.Clock tags) for checked Io timestamp adapters.
// ziglint-ignore: Z023 clock/unit/repr is the consumer contract, matching Duration(unit, repr)
pub fn Instant(comptime ClockTag: anytype, comptime unit: Unit, comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        pub const Clock = ClockTag;
        pub const Scale = unit;
        pub const Representation = Repr;
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const DurationToError = ints.Checked(Repr).SubError;
        pub const ConvertError = error{ Overflow, Inexact };
        pub const CorrespondError = AddError || SubError;
        pub const ToIoTimestampError = ConvertError;
        pub const FromIoTimestampError = ConvertError || error{ClockMismatch};
        pub inline fn fromRaw(value: Repr) Self {
            return @fromBackingInt(value);
        }
        pub inline fn raw(self: Self) Repr {
            return @backingInt(self);
        }
        pub inline fn add(self: Self, span: Duration(unit, Repr)) AddError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).add(span.raw())).raw());
        }
        pub inline fn sub(self: Self, span: Duration(unit, Repr)) SubError!Self {
            return fromRaw((try ints.Checked(Repr).init(@backingInt(self)).sub(span.raw())).raw());
        }
        pub inline fn durationTo(self: Self, other: Self) DurationToError!Duration(unit, Repr) {
            return Duration(unit, Repr).fromRaw((try ints.Checked(Repr).init(@backingInt(other)).sub(@backingInt(self))).raw());
        }
        pub inline fn convert(self: Self, comptime target: Unit, comptime Target: type, rounding: Rounding) ConvertError!Instant(ClockTag, target, Target) {
            return Instant(ClockTag, target, Target).fromRaw(try scaled(Target, unit.nanoseconds(), target.nanoseconds(), @backingInt(self), rounding));
        }
        /// Caller supplies simultaneous samples; trust/uncertainty of sampling remains theirs.
        /// Convert scale/representation explicitly before providing the correspondence.
        pub inline fn correspond(self: Self, source_sample: Self, target_sample: anytype) CorrespondError!@TypeOf(target_sample) {
            const Target = @TypeOf(target_sample);
            if (Target != Instant(Target.Clock, unit, Repr)) @compileError("clock correspondence requires matching scale and representation");
            const offset = try source_sample.durationTo(self);
            return target_sample.add(offset);
        }
        pub inline fn toIoTimestamp(self: Self) ToIoTimestampError!std.Io.Clock.Timestamp {
            const clock: std.Io.Clock = ClockTag;
            return .{ .clock = clock, .raw = .fromNanoseconds(try scaled(i96, unit.nanoseconds(), 1, @backingInt(self), .exact)) };
        }
        pub inline fn fromIoTimestamp(value: std.Io.Clock.Timestamp, rounding: Rounding) FromIoTimestampError!Self {
            const clock: std.Io.Clock = ClockTag;
            if (value.clock != clock) return error.ClockMismatch;
            return fromRaw(try scaled(Repr, 1, unit.nanoseconds(), value.raw.nanoseconds, rounding));
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}
