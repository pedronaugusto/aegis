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

/// A scale reduced to lowest terms. A type function, so each distinct scale is reduced once, in its own
/// comptime evaluation, however many conversions a caller's inline loops instantiate.
fn Ratio(comptime numerator: u64, comptime denominator: u64) type {
    // Euclid's remainder steps stay within the default comptime branch budget for any u64 pair.
    const gcd = blk: {
        var x = numerator;
        var y = denominator;
        while (y != 0) {
            const rest = x % y;
            x = y;
            y = rest;
        }
        break :blk x;
    };
    return struct {
        const n: u64 = numerator / gcd;
        const d: u64 = denominator / gcd;
    };
}

// Wide exact intermediate avoids falsely rejecting a representable quotient.
// Every accepted scale is u64; input bits + 65 includes product and sign.
inline fn scaled(comptime Target: type, comptime numerator: u64, comptime denominator: u64, value: anytype, rounding: Rounding) ScaleError!Target {
    scalar.integer(Target);
    const Source = @TypeOf(value);
    scalar.integer(Source);
    if (comptime @typeInfo(Target).int.signedness == .unsigned) {
        if (value < 0) return error.Overflow;
    }
    const n = Ratio(numerator, denominator).n;
    const d = Ratio(numerator, denominator).d;
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

/// Whether every `Source` value scaled by numerator/denominator fits `Target` under any rounding,
/// decided from the two ranges alone. An unsigned target never takes a signed source.
fn fits(comptime Source: type, comptime Target: type, comptime numerator: u64, comptime denominator: u64) bool {
    if (@typeInfo(Target).int.signedness == .unsigned and @typeInfo(Source).int.signedness == .signed) return false;
    const n: comptime_int = Ratio(numerator, denominator).n;
    const d: comptime_int = Ratio(numerator, denominator).d;
    const low = @divFloor(std.math.minInt(Source) * n, d);
    const high = -@divFloor(-(std.math.maxInt(Source) * n), d);
    return low >= std.math.minInt(Target) and high <= std.math.maxInt(Target);
}

/// What converting a `Source` to `Target` by numerator/denominator can fail with, decided at compile
/// time: `Target` itself when every value converts exactly, otherwise only the errors that can occur.
fn Converted(comptime Source: type, comptime Target: type, comptime numerator: u64, comptime denominator: u64) type {
    const overflow = !fits(Source, Target, numerator, denominator);
    const inexact = Ratio(numerator, denominator).d != 1;
    if (!overflow and !inexact) return Target;
    const Overflow = if (overflow) error{Overflow} else error{};
    const Inexact = if (inexact) error{Inexact} else error{};
    return (Overflow || Inexact)!Target;
}

/// The error set of a conversion result, empty when it cannot fail.
fn ErrorOf(comptime Result: type) type {
    return switch (@typeInfo(Result)) {
        .error_union => |info| info.error_set,
        else => error{},
    };
}

/// `Value` when `Err` is empty, else `Err!Value`: a conversion that cannot fail carries no error.
fn Wrapped(comptime Err: type, comptime Value: type) type {
    return if (@typeInfo(Err).error_set.error_names.?.len == 0) Value else Err!Value;
}

/// `scaled` with its result narrowed to what the ranges allow: no error branch and no range check
/// where the source always fits, which is what lets a std timestamp widen into a wide enough
/// representation for free. A conversion that can lose data keeps its checks.
inline fn scaledFor(comptime Target: type, comptime numerator: u64, comptime denominator: u64, value: anytype, rounding: Rounding) Converted(@TypeOf(value), Target, numerator, denominator) {
    const Source = @TypeOf(value);
    const n = Ratio(numerator, denominator).n;
    const d = Ratio(numerator, denominator).d;
    if (comptime fits(Source, Target, numerator, denominator)) {
        const wide = @Int(.signed, @bitSizeOf(Source) + 65);
        const product = @as(wide, value) * n;
        if (comptime d == 1) return @truncate(product);
        const remainder = @mod(product, d);
        return switch (rounding) {
            .exact => if (remainder == 0) @truncate(@divTrunc(product, d)) else error.Inexact,
            .down => @truncate(@divFloor(product, d)),
            .up => @truncate(@divFloor(product, d) + @intFromBool(remainder != 0)),
        };
    }
    return scaled(Target, numerator, denominator, value, rounding) catch |err| switch (err) {
        error.Overflow => error.Overflow,
        error.Inexact => if (comptime d == 1) unreachable else error.Inexact, // unreachable: a whole-number scale is never inexact
    };
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
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
        pub inline fn compare(self: Self, other: Self) std.math.Order {
            return std.math.order(@backingInt(self), @backingInt(other));
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
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
        pub inline fn compare(self: Self, other: Self) std.math.Order {
            return std.math.order(@backingInt(self), @backingInt(other));
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
        pub inline fn eql(self: Self, other: Self) bool {
            return @backingInt(self) == @backingInt(other);
        }
        pub inline fn compare(self: Self, other: Self) std.math.Order {
            return std.math.order(@backingInt(self), @backingInt(other));
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
        /// Empty when every duration widens into std's nanoseconds, which is the case for any unit of an
        /// `i64` up to seconds and for every unit of 32-bit and narrower representations.
        pub const ToIoDurationError = ErrorOf(Converted(Repr, i96, unit.nanoseconds(), 1));
        /// Empty when std's whole nanosecond range fits this representation and unit exactly: a nanosecond
        /// `i128`. Otherwise Overflow for a narrowing and Inexact for a unit coarser than a nanosecond.
        pub const FromIoDurationError = ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds()));
        pub inline fn fromRaw(value: Repr) Self {
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
        /// A failure-free value when `ToIoDurationError` is empty: no error, no range check.
        pub inline fn toIoDuration(self: Self) Wrapped(ToIoDurationError, std.Io.Duration) {
            const nanoseconds = scaledFor(i96, unit.nanoseconds(), 1, @backingInt(self), .exact);
            if (comptime ToIoDurationError == error{}) return .fromNanoseconds(nanoseconds);
            return .fromNanoseconds(try nanoseconds);
        }
        /// A failure-free value when `FromIoDurationError` is empty: no error, no range check.
        pub inline fn fromIoDuration(value: std.Io.Duration, rounding: Rounding) Wrapped(FromIoDurationError, Self) {
            const converted = scaledFor(Repr, 1, unit.nanoseconds(), value.nanoseconds, rounding);
            if (comptime FromIoDurationError == error{}) return fromRaw(converted);
            return fromRaw(try converted);
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
        /// Empty when every instant widens into std's nanoseconds, as for a `Duration` of this unit.
        pub const ToTimestampError = ErrorOf(Converted(Repr, i96, unit.nanoseconds(), 1));
        /// Empty when std's whole nanosecond range fits this representation and unit exactly.
        pub const FromTimestampError = ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds()));
        pub const ToIoTimestampError = ToTimestampError;
        pub const FromIoTimestampError = FromTimestampError || error{ClockMismatch};
        pub inline fn fromRaw(value: Repr) Self {
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
        /// The instant as std's clock-free timestamp, which is what `Io.Clock.now` returns; the clock is this
        /// type's. No error and no range check when `ToTimestampError` is empty.
        pub inline fn toTimestamp(self: Self) Wrapped(ToTimestampError, std.Io.Timestamp) {
            const nanoseconds = scaledFor(i96, unit.nanoseconds(), 1, @backingInt(self), .exact);
            if (comptime ToTimestampError == error{}) return .fromNanoseconds(nanoseconds);
            return .fromNanoseconds(try nanoseconds);
        }
        /// An instant of this type's clock from the timestamp `Io.Clock.now` returned, with no clock to
        /// check. No error and no range check when `FromTimestampError` is empty.
        pub inline fn fromTimestamp(value: std.Io.Timestamp, rounding: Rounding) Wrapped(FromTimestampError, Self) {
            const converted = scaledFor(Repr, 1, unit.nanoseconds(), value.nanoseconds, rounding);
            if (comptime FromTimestampError == error{}) return fromRaw(converted);
            return fromRaw(try converted);
        }
        /// The instant as a timestamp tagged with this type's clock.
        pub inline fn toIoTimestamp(self: Self) Wrapped(ToIoTimestampError, std.Io.Clock.Timestamp) {
            const clock: std.Io.Clock = ClockTag;
            if (comptime ToTimestampError == error{}) return self.toTimestamp().withClock(clock);
            return (try self.toTimestamp()).withClock(clock);
        }
        pub inline fn fromIoTimestamp(value: std.Io.Clock.Timestamp, rounding: Rounding) FromIoTimestampError!Self {
            const clock: std.Io.Clock = ClockTag;
            if (value.clock != clock) return error.ClockMismatch;
            if (comptime FromTimestampError == error{}) return fromTimestamp(value.raw, rounding);
            return try fromTimestamp(value.raw, rounding);
        }
        pub inline fn encode(self: Self, endian: std.builtin.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.builtin.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}
