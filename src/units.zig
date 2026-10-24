//! Scalar units with explicit, checked conversion; no scheduler or implicit clock cast.
const std = @import("std");
const ints = @import("int.zig");
const scalar = @import("scalar.zig");
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

/// `ints.cast` as an error union whatever the ranges, for the generic scaling kernel below.
inline fn fallible(comptime Target: type, value: anytype) ints.CastError!Target {
    return ints.cast(Target, value);
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
        const input = try fallible(Target, value);
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
        return fallible(Target, result);
    }

    const wide = @Int(.signed, @bitSizeOf(Source) + 65);
    const product = @as(wide, value) * n;
    const remainder = @mod(product, d);
    const result = switch (rounding) {
        .exact => if (remainder == 0) @divTrunc(product, d) else return error.Inexact,
        .down => @divFloor(product, d),
        .up => @divFloor(product, d) + @intFromBool(remainder != 0),
    };
    return fallible(Target, result);
}

/// Whether every `Source` value scaled by numerator/denominator fits `Target` under any rounding,
/// decided from the two ranges alone. An unsigned target never takes a signed source.
fn fits(comptime Source: type, comptime Target: type, comptime numerator: u64, comptime denominator: u64) bool {
    if (@typeInfo(Target).int.signedness == .unsigned and @typeInfo(Source).int.signedness == .signed) return false;
    const n: comptime_int = Ratio(numerator, denominator).n;
    const d: comptime_int = Ratio(numerator, denominator).d;
    if (Source == Target and n == 1 and d == 1) return true;
    // usize and isize are the widest as a source and the narrowest as a target that any supported target has.
    const source_min = if (Source == isize) std.math.minInt(i64) else std.math.minInt(Source);
    const source_max = if (Source == usize) std.math.maxInt(u64) else if (Source == isize) std.math.maxInt(i64) else std.math.maxInt(Source);
    const target_min = if (Target == isize) std.math.minInt(i32) else std.math.minInt(Target);
    const target_max = if (Target == usize) std.math.maxInt(u32) else if (Target == isize) std.math.maxInt(i32) else std.math.maxInt(Target);
    const low = @divFloor(source_min * n, d);
    const high = -@divFloor(-(source_max * n), d);
    return low >= target_min and high <= target_max;
}

/// What converting a `Source` to `Target` by numerator/denominator can fail with, decided at compile
/// time: `Target` itself when every value converts exactly, otherwise only the errors that can occur.
fn Converted(comptime Source: type, comptime Target: type, comptime numerator: u64, comptime denominator: u64, comptime rounding: Rounding) type {
    // A caller's inline loop over many scales and widths shares one evaluation; each scale is reduced once.
    @setEvalBranchQuota(20_000);
    const overflow = !fits(Source, Target, numerator, denominator);
    // Only an exact conversion can be inexact: rounding down or up always has an answer.
    const inexact = Ratio(numerator, denominator).d != 1 and rounding == .exact;
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
inline fn scaledFor(comptime Target: type, comptime numerator: u64, comptime denominator: u64, comptime rounding: Rounding, value: anytype) Converted(@TypeOf(value), Target, numerator, denominator, rounding) {
    const Source = @TypeOf(value);
    const n = Ratio(numerator, denominator).n;
    const d = Ratio(numerator, denominator).d;
    if (comptime fits(Source, Target, numerator, denominator)) {
        // The same scale is a widening or the identity: the value itself, with no wide product to narrow again.
        if (comptime n == 1 and d == 1) return value;
        // The wide type has the target's signedness, so the narrowing is a plain truncate: an unsigned target
        // only ever takes an unsigned source here.
        const wide = @Int(@typeInfo(Target).int.signedness, @bitSizeOf(Source) + 65);
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
        error.Inexact => if (comptime d == 1 or rounding != .exact) unreachable else error.Inexact, // unreachable: only an exact conversion by a fraction is inexact
    };
}

// Text: one grammar for every reader of a duration or a size, a command line, a configuration file or a log.

/// What reading a unit's text fails with: text the grammar does not take (`Malformed`), a value the
/// representation cannot hold (`Overflow`), or one finer than the type holds (`Inexact`). Never a rounding.
const TextError = error{ Malformed, Overflow, Inexact };

/// Wide enough for the largest magnitude of `Repr` times any unit text names (a day is under 2^47
/// nanoseconds, a yobibyte 2^80 bytes), so the checks below run before anything could wrap.
fn Wide(comptime Repr: type) type {
    return @Int(.unsigned, @bitSizeOf(Repr) + 128);
}

/// The largest magnitude a value of `Repr` has in either sign.
fn magnitudeLimit(comptime Repr: type) Wide(Repr) {
    if (@typeInfo(Repr).int.signedness == .unsigned) return std.math.maxInt(Repr);
    return @as(Wide(Repr), 1) << (@bitSizeOf(Repr) - 1);
}

/// The magnitude as `Repr`, negated when `negative`; `Overflow` where it does not fit. `-0` is zero.
fn signed(comptime Repr: type, negative: bool, magnitude: Wide(Repr)) TextError!Repr {
    if (!negative) return std.math.cast(Repr, magnitude) orelse error.Overflow;
    if (magnitude == 0) return 0;
    if (comptime @typeInfo(Repr).int.signedness == .unsigned) return error.Overflow;
    if (magnitude > magnitudeLimit(Repr)) return error.Overflow;
    const Negated = @Int(.signed, @bitSizeOf(Repr) + 1);
    return @intCast(-@as(Negated, @intCast(magnitude))); // safe: the magnitude is at most the negative bound of Repr
}

/// A decimal number at the start of a text: digits, then `.` and digits or nothing.
const Decimal = struct { whole: []const u8, fraction: []const u8, len: usize };

fn decimal(text: []const u8) ?Decimal {
    const whole = digits(text);
    if (whole == 0) return null;
    if (whole == text.len or text[whole] != '.') return .{ .whole = text[0..whole], .fraction = "", .len = whole };
    const fraction = digits(text[whole + 1 ..]);
    if (fraction == 0) return null;
    return .{ .whole = text[0..whole], .fraction = text[whole + 1 ..][0..fraction], .len = whole + 1 + fraction };
}

fn digits(text: []const u8) usize {
    for (text, 0..) |c, i| if (!std.ascii.isDigit(c)) return i;
    return text.len;
}

/// `number` times `scale`, exactly: `Inexact` where the fraction leaves part of one, `Overflow` past `bound`.
fn scaledDecimal(comptime W: type, number: Decimal, scale: W, bound: W) TextError!W {
    var whole: W = 0;
    for (number.whole) |c| {
        whole = whole * 10 + (c - '0');
        if (whole > bound) return error.Overflow;
    }
    // Horner's rule from the last digit: the carry stays below ten scales, and a step that leaves a remainder
    // makes the whole fraction inexact, since the digits before it are whole tenths of what follows.
    var carry: W = 0;
    var i = number.fraction.len;
    while (i > 0) {
        i -= 1;
        if (carry % 10 != 0) return error.Inexact;
        carry = (number.fraction[i] - '0') * scale + carry / 10;
    }
    if (carry % 10 != 0) return error.Inexact;
    const total = whole * scale + carry / 10;
    if (total > bound) return error.Overflow;
    return total;
}

/// The units a duration's text names, coarsest first; `format` writes the first symbol of each.
const span_units = [_]struct { unit: Unit, symbols: []const []const u8 }{
    .{ .unit = .day, .symbols = &.{"d"} },
    .{ .unit = .hour, .symbols = &.{"h"} },
    .{ .unit = .minute, .symbols = &.{"m"} },
    .{ .unit = .second, .symbols = &.{"s"} },
    .{ .unit = .millisecond, .symbols = &.{"ms"} },
    .{ .unit = .microsecond, .symbols = &.{ "us", "\u{b5}s", "\u{3bc}s" } },
    .{ .unit = .nanosecond, .symbols = &.{"ns"} },
};

/// The longest unit symbol that starts `text`, by its place in `span_units`.
const Symbol = struct { place: usize, len: usize };

fn spanSymbol(text: []const u8) ?Symbol {
    var found: ?Symbol = null;
    for (span_units, 0..) |entry, place| for (entry.symbols) |symbol| {
        const longer = if (found) |f| symbol.len > f.len else true;
        if (longer and std.mem.startsWith(u8, text, symbol)) found = .{ .place = place, .len = symbol.len };
    };
    return found;
}

/// A span of `unit` read from `text`, in the grammar `Duration.parse` describes.
fn parseSpan(comptime Repr: type, comptime unit: Unit, text: []const u8) TextError!Repr {
    const W = Wide(Repr);
    const scale: W = unit.nanoseconds();
    const bound = magnitudeLimit(Repr) * scale;
    const negative = text.len != 0 and text[0] == '-';
    var rest: []const u8 = text[@intFromBool(negative)..];
    if (rest.len == 0) return error.Malformed;
    var total: W = 0;
    if (!std.mem.eql(u8, rest, "0")) {
        // The first place in `span_units` the next component may name: units descend, each at most once.
        var next: usize = 0;
        while (rest.len != 0) {
            const number = decimal(rest) orelse return error.Malformed;
            rest = rest[number.len..];
            const symbol = spanSymbol(rest) orelse return error.Malformed;
            if (symbol.place < next) return error.Malformed;
            next = symbol.place + 1;
            rest = rest[symbol.len..];
            total += try scaledDecimal(W, number, span_units[symbol.place].unit.nanoseconds(), bound - total);
        }
    }
    if (total % scale != 0) return error.Inexact;
    return signed(Repr, negative, total / scale);
}

/// Writes a span of `unit` in the canonical form `Duration.format` describes.
fn formatSpan(comptime Repr: type, comptime unit: Unit, value: Repr, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (value == 0) return w.writeAll("0s");
    if (value < 0) try w.writeByte('-');
    var rest = @as(Wide(Repr), @abs(value)) * unit.nanoseconds();
    for (span_units) |entry| {
        const step: Wide(Repr) = entry.unit.nanoseconds();
        if (rest >= step) try w.print("{d}{s}", .{ rest / step, entry.symbols[0] });
        rest %= step;
    }
}

/// The number of decimal digits of `value`.
fn decimalDigits(comptime value: anytype) usize {
    var len: usize = 1;
    var rest = value;
    while (rest >= 10) : (rest /= 10) len += 1;
    return len;
}

/// The most bytes `formatSpan` writes for a span of `unit` and `Repr`: a sign, then each component at its
/// largest, which below the coarsest is one short of the unit above it, and none finer than `unit`.
fn spanTextCapacity(comptime Repr: type, comptime unit: Unit) usize {
    const most = magnitudeLimit(Repr) * unit.nanoseconds();
    var len: usize = 1;
    var above: ?u64 = null;
    for (span_units) |entry| {
        const step = entry.unit.nanoseconds();
        if (step < unit.nanoseconds()) break;
        const largest = if (above) |coarser| @min(most / step, coarser / step - 1) else most / step;
        if (largest != 0) len += decimalDigits(largest) + entry.symbols[0].len;
        above = step;
    }
    return len;
}

/// The units a size's text names, largest first: each binary unit (1024^n) above its decimal one (1000^n).
const size_units = [_]struct { symbol: []const u8, bytes: u128 }{
    .{ .symbol = "YiB", .bytes = 1 << 80 },
    .{ .symbol = "YB", .bytes = 1_000_000_000_000_000_000_000_000 },
    .{ .symbol = "ZiB", .bytes = 1 << 70 },
    .{ .symbol = "ZB", .bytes = 1_000_000_000_000_000_000_000 },
    .{ .symbol = "EiB", .bytes = 1 << 60 },
    .{ .symbol = "EB", .bytes = 1_000_000_000_000_000_000 },
    .{ .symbol = "PiB", .bytes = 1 << 50 },
    .{ .symbol = "PB", .bytes = 1_000_000_000_000_000 },
    .{ .symbol = "TiB", .bytes = 1 << 40 },
    .{ .symbol = "TB", .bytes = 1_000_000_000_000 },
    .{ .symbol = "GiB", .bytes = 1 << 30 },
    .{ .symbol = "GB", .bytes = 1_000_000_000 },
    .{ .symbol = "MiB", .bytes = 1 << 20 },
    .{ .symbol = "MB", .bytes = 1_000_000 },
    .{ .symbol = "KiB", .bytes = 1 << 10 },
    .{ .symbol = "kB", .bytes = 1_000 },
    .{ .symbol = "B", .bytes = 1 },
};

/// A size read from `text`, in the grammar `Bytes.parse` describes.
fn parseSize(comptime Repr: type, text: []const u8) TextError!Repr {
    const negative = text.len != 0 and text[0] == '-';
    const rest = text[@intFromBool(negative)..];
    const number = decimal(rest) orelse return error.Malformed;
    const suffix = rest[number.len..];
    const scale: u128 = if (suffix.len == 0) 1 else for (size_units) |entry| {
        if (std.mem.eql(u8, suffix, entry.symbol)) break entry.bytes;
    } else return error.Malformed;
    return signed(Repr, negative, try scaledDecimal(Wide(Repr), number, scale, magnitudeLimit(Repr)));
}

/// Writes a size in the canonical form `Bytes.format` describes.
fn formatSize(comptime Repr: type, value: Repr, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (value == 0) return w.writeAll("0B");
    if (value < 0) try w.writeByte('-');
    const magnitude: Wide(Repr) = @abs(value);
    for (size_units) |entry| {
        if (magnitude % entry.bytes == 0) return w.print("{d}{s}", .{ magnitude / entry.bytes, entry.symbol });
    }
    unreachable; // unreachable: the last unit is one byte, which divides every size
}

/// Count domains are distinct; multiplying by a scalar retains that domain.
pub fn Count(comptime Tag: type, comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// The tag that keeps these counts apart from every other domain's.
        pub const Domain = Tag;
        /// The integer the count is held in.
        pub const Representation = Repr;
        /// This scalar as generic code built on any aegis version reads it (README, "Generic code").
        pub const aegis_scalar = .{ .contract = 1, .kind = .count, .representation = Repr, .domain = Tag };
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
        /// No error where every value of this representation fits `Target` on every supported target.
        pub inline fn convert(self: Self, comptime Target: type) ints.Lifted(Repr, Target, Count(Tag, Target)) {
            const converted = ints.cast(Target, @backingInt(self));
            if (comptime scalar.lossless(Repr, Target)) return Count(Tag, Target).fromRaw(converted);
            return Count(Tag, Target).fromRaw(try converted);
        }
        pub inline fn encode(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.lang.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Distinct bytes count, never an implicit unit conversion.
pub fn Bytes(comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// The integer the count of bytes is held in.
        pub const Representation = Repr;
        /// This scalar as generic code built on any aegis version reads it (README, "Generic code").
        pub const aegis_scalar = .{ .contract = 1, .kind = .bytes, .representation = Repr };
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
        /// No error where every value of this representation fits `Target` on every supported target.
        pub inline fn convert(self: Self, comptime Target: type) ints.Lifted(Repr, Target, Bytes(Target)) {
            const converted = ints.cast(Target, @backingInt(self));
            if (comptime scalar.lossless(Repr, Target)) return Bytes(Target).fromRaw(converted);
            return Bytes(Target).fromRaw(try converted);
        }
        pub const ToBitsError = error{ Overflow, Inexact };
        pub inline fn toBits(self: Self) ToBitsError!Bits(Repr) {
            return Bits(Repr).fromRaw(try scaled(Repr, 8, 1, @backingInt(self), .exact));
        }
        /// `Malformed` for text that is no size, `Overflow` for one this representation cannot hold,
        /// `Inexact` for one that leaves part of a byte.
        pub const ParseError = TextError;
        /// The most bytes `format` writes, for a buffer that holds any size of this type.
        pub const max_text_len: usize = 1 + decimalDigits(magnitudeLimit(Repr)) + "YiB".len;
        /// Reads a size: a decimal number and a unit, or a number of bytes alone (`4096`, `4096B`, `64MiB`,
        /// `1.5GB`). Binary units are powers of 1024 (`KiB`, `MiB`, `GiB`, `TiB`, `PiB`, `EiB`, `ZiB`, `YiB`)
        /// and decimal ones powers of 1000 (`kB`, `MB`, `GB`, `TB`, `PB`, `EB`, `ZB`, `YB`), spelled exactly
        /// so: `KB`, `mb` or `kiB` is `Malformed`, never taken for one or the other. A leading `-` negates.
        /// The value is exact: `0.1KiB` is `Inexact`, never rounded to a byte.
        pub fn parse(text: []const u8) ParseError!Self {
            return fromRaw(try parseSize(Repr, text));
        }
        /// A size written as `parse` reads it and known at compile time, checked there: for a default or
        /// a constant, `.literal("64KiB")` where `parse` would need a `catch`. Text `parse` refuses is a
        /// compile error naming why.
        pub fn literal(comptime text: []const u8) Self {
            return comptime parse(text) catch |err| @compileError("not a size of " ++ @typeName(Repr) ++ ": \"" ++ text ++ "\" (" ++ @errorName(err) ++ ")");
        }
        /// Writes the size as `parse` reads it back: a whole number of the largest unit, binary or decimal,
        /// that divides it (`64MiB`, `1500kB`, `1GB`), else of bytes (`1500B`), and `0B` for zero.
        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            return formatSize(Repr, @backingInt(self), w);
        }
        pub inline fn encode(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.lang.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Distinct bits count, never an implicit unit conversion.
pub fn Bits(comptime Repr: type) type {
    scalar.abiInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// The integer the count of bits is held in.
        pub const Representation = Repr;
        /// This scalar as generic code built on any aegis version reads it (README, "Generic code").
        pub const aegis_scalar = .{ .contract = 1, .kind = .bits, .representation = Repr };
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
        /// No error where every value of this representation fits `Target` on every supported target.
        pub inline fn convert(self: Self, comptime Target: type) ints.Lifted(Repr, Target, Bits(Target)) {
            const converted = ints.cast(Target, @backingInt(self));
            if (comptime scalar.lossless(Repr, Target)) return Bits(Target).fromRaw(converted);
            return Bits(Target).fromRaw(try converted);
        }
        pub const ToBytesError = error{ Overflow, Inexact };
        pub const ToBytesRoundedError = ToBytesError;
        pub inline fn toBytes(self: Self) ToBytesError!Bytes(Repr) {
            return Bytes(Repr).fromRaw(try scaled(Repr, 1, 8, @backingInt(self), .exact));
        }
        pub inline fn toBytesRounded(self: Self, rounding: Rounding) ToBytesRoundedError!Bytes(Repr) {
            return Bytes(Repr).fromRaw(try scaled(Repr, 1, 8, @backingInt(self), rounding));
        }
        pub inline fn encode(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.lang.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// Signed representations permit negative spans; unsigned conversion rejects negative input.
pub fn Duration(comptime unit: Unit, comptime Repr: type) type {
    scalar.wholeByteInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// The unit one step of the representation is.
        pub const Scale = unit;
        /// The integer the span is held in.
        pub const Representation = Repr;
        /// This scalar as generic code built on any aegis version reads it (README, "Generic code").
        pub const aegis_scalar = .{ .contract = 1, .kind = .duration, .representation = Repr, .unit = unit };
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const MulError = ints.Checked(Repr).MulError;
        pub const ConvertError = error{ Overflow, Inexact };
        /// Empty when every duration widens into std's nanoseconds, which is the case for any unit of an
        /// `i64` up to seconds and for every unit of 32-bit and narrower representations.
        pub const ToIoDurationError = ErrorOf(Converted(Repr, i96, unit.nanoseconds(), 1, .exact));
        /// Empty when std's whole nanosecond range fits this representation and unit exactly: a nanosecond
        /// `i128`. Otherwise Overflow for a narrowing and Inexact for a unit coarser than a nanosecond.
        pub const FromIoDurationError = ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), .exact));
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
        /// Clamped at the representation's bounds instead of failing, for a clock that saturates on purpose.
        pub inline fn saturatingAdd(self: Self, rhs: Self) Self {
            return fromRaw(@backingInt(self) +| @backingInt(rhs));
        }
        pub inline fn saturatingSub(self: Self, rhs: Self) Self {
            return fromRaw(@backingInt(self) -| @backingInt(rhs));
        }
        pub inline fn saturatingMul(self: Self, rhs: Repr) Self {
            return fromRaw(@backingInt(self) *| rhs);
        }
        /// The same value in another unit and representation. It carries no error where every value of this
        /// representation converts exactly, no range check where none can fail, and only the errors that can
        /// occur otherwise (`ConvertError` is the widest set).
        pub inline fn convert(self: Self, comptime target: Unit, comptime Target: type, comptime rounding: Rounding) Wrapped(ErrorOf(Converted(Repr, Target, unit.nanoseconds(), target.nanoseconds(), rounding)), Duration(target, Target)) {
            const converted = scaledFor(Target, unit.nanoseconds(), target.nanoseconds(), rounding, @backingInt(self));
            if (comptime ErrorOf(Converted(Repr, Target, unit.nanoseconds(), target.nanoseconds(), rounding)) == error{}) return Duration(target, Target).fromRaw(converted);
            return Duration(target, Target).fromRaw(try converted);
        }
        /// `Malformed` for text that is no duration, `Overflow` for one this representation cannot hold,
        /// `Inexact` for one finer than `Scale`.
        pub const ParseError = TextError;
        /// The most bytes `format` writes, for a buffer that holds any duration of this type.
        pub const max_text_len: usize = spanTextCapacity(Repr, unit);
        /// Reads a duration: one or more components, each a decimal number and a unit, from the coarsest unit
        /// to the finest and each unit at most once (`30s`, `1m30s`, `250ms`, `1.5h`, `2d12h`). The units are
        /// `d` (86400 seconds), `h`, `m`, `s`, `ms`, `us` (or `µs`) and `ns`. A leading `-` negates, and `0`
        /// alone is zero. The value is exact: `Inexact` where it is finer than `Scale` (`1.5s` as whole
        /// seconds, `1m30s` as whole minutes), `Overflow` where the representation cannot hold it (any negative
        /// one in an unsigned representation), `Malformed` for anything else, spaces included.
        pub fn parse(text: []const u8) ParseError!Self {
            return fromRaw(try parseSpan(Repr, unit, text));
        }
        /// A duration written as `parse` reads it and known at compile time, checked there: for a default
        /// or a constant, `.literal("250ms")` where `parse` would need a `catch`. Text `parse` refuses is a
        /// compile error naming why.
        pub fn literal(comptime text: []const u8) Self {
            return comptime parse(text) catch |err| @compileError("not a duration of " ++ @typeName(Repr) ++ ": \"" ++ text ++ "\" (" ++ @errorName(err) ++ ")");
        }
        /// Writes the duration as `parse` reads it back: a component for each unit from days down to
        /// nanoseconds, leaving out the zero ones (`1m30s`, `2d12h`, `-250ms`), and `0s` for zero.
        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            return formatSpan(Repr, unit, @backingInt(self), w);
        }
        /// A failure-free value when `ToIoDurationError` is empty: no error, no range check.
        pub inline fn toIoDuration(self: Self) Wrapped(ToIoDurationError, std.Io.Duration) {
            const nanoseconds = scaledFor(i96, unit.nanoseconds(), 1, .exact, @backingInt(self));
            if (comptime ToIoDurationError == error{}) return .fromNanoseconds(nanoseconds);
            return .fromNanoseconds(try nanoseconds);
        }
        /// A failure-free value when `FromIoDurationError` is empty: no error, no range check.
        pub inline fn fromIoDuration(value: std.Io.Duration, comptime rounding: Rounding) Wrapped(ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)), Self) {
            const converted = scaledFor(Repr, 1, unit.nanoseconds(), rounding, value.nanoseconds);
            if (comptime ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)) == error{}) return fromRaw(converted);
            return fromRaw(try converted);
        }
        pub inline fn encode(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.lang.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}

/// A point in a caller-owned clock/epoch. No instant+instant or numerical clock cast.
/// Use .real/.awake/.boot (std.Io.Clock tags) for checked Io timestamp adapters.
// ziglint-ignore: Z023 clock/unit/repr is the consumer contract, matching Duration(unit, repr)
pub fn Instant(comptime ClockTag: anytype, comptime unit: Unit, comptime Repr: type) type {
    scalar.wholeByteInteger(Repr);
    return enum(Repr) {
        const Self = @This();
        /// The clock the instant is read from.
        pub const Clock = ClockTag;
        /// The unit one step of the representation is.
        pub const Scale = unit;
        /// The integer the instant is held in.
        pub const Representation = Repr;
        /// This scalar as generic code built on any aegis version reads it (README, "Generic code").
        pub const aegis_scalar = .{ .contract = 1, .kind = .instant, .representation = Repr, .unit = unit, .clock = ClockTag };
        /// Private: use fromRaw/raw.
        _,
        pub const AddError = ints.Checked(Repr).AddError;
        pub const SubError = ints.Checked(Repr).SubError;
        pub const DurationToError = ints.Checked(Repr).SubError;
        pub const ConvertError = error{ Overflow, Inexact };
        pub const CorrespondError = AddError || SubError;
        /// Empty when every instant widens into std's nanoseconds, as for a `Duration` of this unit.
        pub const ToTimestampError = ErrorOf(Converted(Repr, i96, unit.nanoseconds(), 1, .exact));
        /// Empty when std's whole nanosecond range fits this representation and unit exactly.
        pub const FromTimestampError = ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), .exact));
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
        /// Clamped at the representation's bounds instead of failing, for a clock that saturates on purpose.
        pub inline fn saturatingAdd(self: Self, span: Duration(unit, Repr)) Self {
            return fromRaw(@backingInt(self) +| span.raw());
        }
        pub inline fn saturatingSub(self: Self, span: Duration(unit, Repr)) Self {
            return fromRaw(@backingInt(self) -| span.raw());
        }
        /// The span from this instant to `other`, clamped at the representation's bounds. For an unsigned
        /// representation an `other` that is earlier gives a zero span: the answer for a clock that stepped back
        /// between two readings, where `durationTo` reports `error.Underflow`.
        pub inline fn saturatingDurationTo(self: Self, other: Self) Duration(unit, Repr) {
            return Duration(unit, Repr).fromRaw(@backingInt(other) -| @backingInt(self));
        }
        pub inline fn convert(self: Self, comptime target: Unit, comptime Target: type, comptime rounding: Rounding) Wrapped(ErrorOf(Converted(Repr, Target, unit.nanoseconds(), target.nanoseconds(), rounding)), Instant(ClockTag, target, Target)) {
            const converted = scaledFor(Target, unit.nanoseconds(), target.nanoseconds(), rounding, @backingInt(self));
            if (comptime ErrorOf(Converted(Repr, Target, unit.nanoseconds(), target.nanoseconds(), rounding)) == error{}) return Instant(ClockTag, target, Target).fromRaw(converted);
            return Instant(ClockTag, target, Target).fromRaw(try converted);
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
            const nanoseconds = scaledFor(i96, unit.nanoseconds(), 1, .exact, @backingInt(self));
            if (comptime ToTimestampError == error{}) return .fromNanoseconds(nanoseconds);
            return .fromNanoseconds(try nanoseconds);
        }
        /// An instant of this type's clock from the timestamp `Io.Clock.now` returned, with no clock to
        /// check. No error and no range check when `FromTimestampError` is empty.
        pub inline fn fromTimestamp(value: std.Io.Timestamp, comptime rounding: Rounding) Wrapped(ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)), Self) {
            const converted = scaledFor(Repr, 1, unit.nanoseconds(), rounding, value.nanoseconds);
            if (comptime ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)) == error{}) return fromRaw(converted);
            return fromRaw(try converted);
        }
        /// The instant as a timestamp tagged with this type's clock.
        pub inline fn toIoTimestamp(self: Self) Wrapped(ToIoTimestampError, std.Io.Clock.Timestamp) {
            const clock: std.Io.Clock = ClockTag;
            if (comptime ToTimestampError == error{}) return self.toTimestamp().withClock(clock);
            return (try self.toTimestamp()).withClock(clock);
        }
        pub inline fn fromIoTimestamp(value: std.Io.Clock.Timestamp, comptime rounding: Rounding) (ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)) || error{ClockMismatch})!Self {
            const clock: std.Io.Clock = ClockTag;
            if (value.clock != clock) return error.ClockMismatch;
            if (comptime ErrorOf(Converted(i96, Repr, 1, unit.nanoseconds(), rounding)) == error{}) return fromTimestamp(value.raw, rounding);
            return try fromTimestamp(value.raw, rounding);
        }
        pub inline fn encode(self: Self, endian: std.lang.Endian) scalar.Bytes(Repr) {
            return scalar.encode(Repr, @backingInt(self), endian);
        }
        pub inline fn decode(data: scalar.Bytes(Repr), endian: std.lang.Endian) Self {
            return fromRaw(scalar.decode(Repr, data, endian));
        }
    };
}
