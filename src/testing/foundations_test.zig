const builtin = @import("builtin");
const std = @import("std");
const aegis = @import("../root.zig");
const t = std.testing;

test "A3 checked extremes stay checked in release" {
    const C = aegis.int.Checked(i8);
    try t.expectError(error.Overflow, C.init(127).add(1));
    try t.expectError(error.Underflow, C.init(-128).sub(1));
    try t.expectError(error.Overflow, C.init(-128).div(-1));
    try t.expectError(error.DivisionByZero, C.init(1).rem(0));
    try t.expectEqual(@as(i8, 0), (try C.init(-128).rem(-1)).raw());
    // A shift past the width is not a `Log2Int(i8)`: it does not compile, and one read from input is
    // narrowed first.
    try t.expectError(error.Overflow, aegis.int.cast(std.math.Log2Int(i8), @as(usize, 8)));
    try t.expectError(error.Overflow, C.init(64).shl(1));
    try t.expectError(error.Underflow, aegis.int.Checked(u8).init(0).sub(1));
    try t.expectError(error.Overflow, aegis.int.Checked(usize).init(std.math.maxInt(usize)).add(1));
}

test "A3 exhaustive checked and saturating arithmetic independent wider oracle" {
    inline for (.{ u8, i8 }) |R| {
        const low = std.math.minInt(R);
        const high = std.math.maxInt(R);
        var a: i32 = low;
        while (a <= high) : (a += 1) {
            var b: i32 = low;
            while (b <= high) : (b += 1) {
                const x: R = @intCast(a); // safe: loop bounds are exactly R's domain
                const y: R = @intCast(b); // safe: loop bounds are exactly R's domain
                inline for (.{ .add, .sub, .mul }) |op| {
                    const expected: i32 = switch (op) {
                        .add => a + b,
                        .sub => a - b,
                        .mul => a * b,
                        else => unreachable,
                    };
                    const got = @field(aegis.int.Checked(R), @tagName(op))(.init(x), y);
                    if (expected < low) try t.expectError(error.Underflow, got) else if (expected > high) try t.expectError(error.Overflow, got) else try t.expectEqual(expected, @as(i32, (try got).raw()));
                    const saturated = @field(aegis.int.Saturating(R), @tagName(op))(.init(x), y);
                    try t.expectEqual(std.math.clamp(expected, low, high), @as(i32, saturated.raw()));
                }
                if (b != 0) {
                    const quotient = @divTrunc(a, b);
                    const got = aegis.int.Checked(R).init(x).div(y);
                    if (quotient > high) try t.expectError(error.Overflow, got) else try t.expectEqual(quotient, @as(i32, (try got).raw()));
                    try t.expectEqual(@rem(a, b), @as(i32, (try aegis.int.Checked(R).init(x).rem(y)).raw()));
                }
            }
        }
    }
}

test "A3 ranged operations and failing casts" {
    const R = aegis.int.Ranged(i16, -10, 10);
    try t.expectError(error.OutOfRange, R.init(11));
    try t.expectError(error.OutOfRange, (try R.init(10)).add(1));
    try t.expectEqual(@as(i16, -10), (try (try R.init(-5)).mul(2)).raw());
    try t.expectError(error.OutOfRange, (try R.init(5)).shl(2));
    try t.expectError(error.Overflow, aegis.int.cast(u8, @as(u16, 256)));
    try t.expectError(error.Overflow, aegis.int.cast(u64, @as(i64, -1)));
    try t.expectEqual(@as(i16, 255), aegis.int.cast(i16, @as(u8, 255)));
    try t.expectEqual(@as(u8, 255), try aegis.int.cast(u8, 255));
    try t.expectError(error.Overflow, aegis.int.cast(u8, -1));
    try t.expectEqual(@as(i8, 127), (try aegis.int.Saturating(i8).init(-128).div(-1)).raw());
    try t.expectError(error.DivisionByZero, aegis.int.Saturating(u8).init(1).div(0));
}

test "A3 checked, saturating and ranged values compare through their own eql and compare" {
    const R = aegis.int.Ranged(i16, -10, 10);
    try t.expect(R.literal(-3).eql(try R.init(-3)));
    try t.expect(!R.literal(-3).eql(R.literal(3)));
    try t.expectEqual(std.math.Order.lt, R.literal(-3).compare(R.literal(3)));
    try t.expectEqual(std.math.Order.gt, R.literal(10).compare(R.literal(-10)));
    try t.expectEqual(std.math.Order.eq, R.literal(0).compare(R.literal(0)));
    const C = aegis.int.Checked(i8);
    try t.expect(C.init(-128).eql(C.init(-128)));
    try t.expectEqual(std.math.Order.lt, C.init(-128).compare(C.init(127)));
    try t.expectEqual(std.math.Order.gt, C.init(1).compare(C.init(-1)));
    const S = aegis.int.Saturating(u8);
    try t.expect(S.init(200).add(100).eql(S.init(255)));
    try t.expectEqual(std.math.Order.lt, S.init(0).compare(S.init(255)));
    try t.expectEqual(std.math.Order.eq, S.init(7).compare(S.init(7)));
}

test "A3 IDs exhaustion and endian encoding" {
    const Tag = enum { request };
    const I = aegis.id.Id(Tag, u16);
    const a = I.fromRaw(0x1234);
    try t.expectEqualSlices(u8, &.{ 0x12, 0x34 }, &a.toBytes(.big));
    try t.expect(a.eql(I.fromBytes(a.toBytes(.little), .little)));
    try t.expectEqual(std.math.Order.lt, I.fromRaw(1).compare(a));
    try t.expectEqual(a.hash(), I.fromRaw(0x1234).hash());
    try t.expectError(error.InvalidId, aegis.id.NonZero(Tag, u8).fromRaw(0));
    var counter = aegis.id.Counter(Tag, u8).init(254);
    try t.expectEqual(@as(u8, 255), (try counter.next()).raw());
    try t.expectError(error.IdExhausted, counter.next());
    try t.expectError(error.IdExhausted, counter.next());
}

test "A3 a size divides into a size or a count, every quotient checked" {
    const B = aegis.units.Bytes(u64);
    try t.expectEqual(B.fromRaw(21), try B.fromRaw(64).divTrunc(3));
    try t.expectError(error.DivisionByZero, B.fromRaw(64).divTrunc(0));
    try t.expectEqual(@as(u64, 16), try B.fromRaw(64 * 1024).ratio(.fromRaw(4096)));
    try t.expectError(error.DivisionByZero, B.fromRaw(1).ratio(.fromRaw(0)));
    const S = aegis.units.Bytes(i32);
    try t.expectEqual(S.fromRaw(-3), try S.fromRaw(-7).divTrunc(2));
    try t.expectError(error.Overflow, S.fromRaw(std.math.minInt(i32)).divTrunc(-1));
    // An oracle over every u8 pair.
    const B8 = aegis.units.Bytes(u8);
    for (0..256) |a| for (1..256) |b| {
        try t.expectEqual(@as(u8, @intCast(a / b)), (try B8.fromRaw(@intCast(a)).divTrunc(@intCast(b))).raw()); // safe: a and b are u8's domain
    };
}

test "A3 units negative rounding range and byte conversion" {
    const D = aegis.units.Duration(.nanosecond, i64);
    try t.expectError(error.Inexact, D.fromRaw(-1001).convert(.microsecond, i64, .exact));
    try t.expectEqual(@as(i64, -2), D.fromRaw(-1001).convert(.microsecond, i64, .down).raw());
    try t.expectEqual(@as(i64, -1), D.fromRaw(-1001).convert(.microsecond, i64, .up).raw());
    try t.expectError(error.Overflow, D.fromRaw(-1000).convert(.microsecond, u64, .exact));
    try t.expectError(error.Overflow, aegis.units.Duration(.second, u64).fromRaw(std.math.maxInt(u64)).convert(.nanosecond, u64, .exact));
    try t.expectEqual(@as(u64, 213503), aegis.units.Duration(.nanosecond, u64).fromRaw(std.math.maxInt(u64)).convert(.day, u32, .down).raw());
    const B = aegis.units.Bits(u64);
    try t.expectError(error.Inexact, B.fromRaw(9).toBytes());
    try t.expectEqual(@as(u64, 2), (try B.fromRaw(9).toBytesRounded(.up)).raw());
    try t.expectEqual(@as(u64, 1), (try B.fromRaw(9).toBytesRounded(.down)).raw());
    try t.expectEqual(@as(u64, std.math.maxInt(u64) / 8 + 1), (try B.fromRaw(std.math.maxInt(u64)).toBytesRounded(.up)).raw());
    try t.expectError(error.Overflow, aegis.units.Bytes(u8).fromRaw(32).toBits());
    const N = aegis.units.Count(struct {}, u8);
    try t.expectError(error.Overflow, N.fromRaw(255).add(N.fromRaw(1)));
    try t.expectEqual(@as(u16, 255), N.fromRaw(255).convert(u16).raw());
}

test "A3 clock domains correspondence and Io adapters" {
    const U = aegis.units;
    const Awake = U.Instant(.awake, .millisecond, i64);
    const Real = U.Instant(.real, .millisecond, i64);
    const a = Awake.fromRaw(10);
    const b = try a.add(U.Duration(.millisecond, i64).fromRaw(3));
    try t.expectEqual(@as(i64, 3), (try a.durationTo(b)).raw());
    try t.expectEqual(@as(i64, 1003), (try b.correspond(a, Real.fromRaw(1000))).raw());
    try t.expectError(error.Overflow, Awake.fromRaw(std.math.maxInt(i64)).add(U.Duration(.millisecond, i64).fromRaw(1)));
    try t.expectError(error.ClockMismatch, Awake.fromIoTimestamp(.{ .raw = .fromNanoseconds(0), .clock = .real }, .exact));
    const stamp = b.toIoTimestamp();
    try t.expectEqual(std.Io.Clock.awake, stamp.clock);
    try t.expectEqual(@as(i96, 13_000_000), stamp.raw.nanoseconds);
    try t.expectEqual(@as(i64, 13), (try Awake.fromIoTimestamp(stamp, .exact)).raw());
    try t.expectEqual(@as(i96, -1_000_000), U.Duration(.millisecond, i64).fromRaw(-1).toIoDuration().nanoseconds);
    try t.expectError(error.Inexact, U.Duration(.millisecond, i64).fromIoDuration(.fromNanoseconds(1), .exact));
}

test "A3 a duration divides by a count, toward zero or negative infinity, refusing zero and the one overflow" {
    const U = aegis.units;
    const D = U.Duration(.millisecond, i8);
    // A quarter of a wait, as a retransmission's ACK timer takes it.
    try t.expectEqual(@as(i8, 25), (try D.fromRaw(100).divTrunc(4)).raw());
    try t.expectEqual(@as(i8, 2), (try D.fromRaw(7).divTrunc(3)).raw());
    try t.expectEqual(@as(i8, 2), (try D.fromRaw(7).divFloor(3)).raw());
    try t.expectEqual(@as(i8, -2), (try D.fromRaw(-7).divTrunc(3)).raw());
    try t.expectEqual(@as(i8, -3), (try D.fromRaw(-7).divFloor(3)).raw());
    try t.expectEqual(@as(i8, 127), (try D.fromRaw(-127).divTrunc(-1)).raw());
    try t.expectError(error.DivisionByZero, D.fromRaw(1).divTrunc(0));
    try t.expectError(error.DivisionByZero, D.fromRaw(1).divFloor(0));
    try t.expectError(error.Overflow, D.fromRaw(-128).divTrunc(-1));
    try t.expectError(error.Overflow, D.fromRaw(-128).divFloor(-1));
    // Unsigned: zero is the one refusal, and the error set says so.
    const M = U.Duration(.second, u8);
    try t.expectEqual(@as(u8, 63), (try M.fromRaw(255).divFloor(4)).raw());
    try t.expectError(error.DivisionByZero, M.fromRaw(1).divTrunc(0));
    comptime std.debug.assert(M.DivError == error{DivisionByZero});
    // Exhaustive against std's own division on a wider integer.
    var x: i16 = -128;
    while (x <= 127) : (x += 1) {
        for ([_]i8{ -128, -3, -1, 1, 2, 7, 127 }) |d| {
            if (x == -128 and d == -1) continue;
            try t.expectEqual(@as(i8, @intCast(@divTrunc(x, d))), (try D.fromRaw(@intCast(x)).divTrunc(d)).raw());
            try t.expectEqual(@as(i8, @intCast(@divFloor(x, d))), (try D.fromRaw(@intCast(x)).divFloor(d)).raw());
        }
    }
}

test "A3 a duration divides by a duration into a count, toward zero or negative infinity, and mod leaves the rest with the divisor's sign" {
    const D = aegis.units.Duration(.nanosecond, i8);
    // An oracle over every i8 pair: the floored identity holds and the remainder lies from zero toward by.
    for (0..256) |x| for (0..256) |y| {
        const a: i8 = @bitCast(@as(u8, @intCast(x))); // safe: x is u8's domain
        const b: i8 = @bitCast(@as(u8, @intCast(y))); // safe: y is u8's domain
        if (b == 0) {
            try t.expectError(error.DivisionByZero, D.fromRaw(a).ratioFloor(.fromRaw(b)));
            try t.expectError(error.DivisionByZero, D.fromRaw(a).ratio(.fromRaw(b)));
            try t.expectError(error.DivisionByZero, D.fromRaw(a).mod(.fromRaw(b)));
            continue;
        }
        const rest = (try D.fromRaw(a).mod(.fromRaw(b))).raw();
        const wide_rest = @as(i16, a) - @divFloor(@as(i16, a), b) * b;
        try t.expectEqual(wide_rest, rest);
        try t.expect(if (b > 0) rest >= 0 and rest < b else rest <= 0 and rest > b);
        if (a == -128 and b == -1) {
            try t.expectError(error.Overflow, D.fromRaw(a).ratioFloor(.fromRaw(b)));
            try t.expectError(error.Overflow, D.fromRaw(a).ratio(.fromRaw(b)));
            continue;
        }
        try t.expectEqual(@divFloor(a, b), try D.fromRaw(a).ratioFloor(.fromRaw(b)));
        try t.expectEqual(@divTrunc(a, b), try D.fromRaw(a).ratio(.fromRaw(b)));
    };
    // Unsigned: every u8 pair.
    const U = aegis.units.Duration(.second, u8);
    for (0..256) |x| for (1..256) |y| {
        const a: u8 = @intCast(x); // safe: x is u8's domain
        const b: u8 = @intCast(y); // safe: y is u8's domain
        try t.expectEqual(a / b, try U.fromRaw(a).ratioFloor(.fromRaw(b)));
        try t.expectEqual(a % b, (try U.fromRaw(a).mod(.fromRaw(b))).raw());
    };
    // Days and the time of day of an instant before the epoch, as a calendar takes them.
    const Ns = aegis.units.Duration(.nanosecond, i128);
    const day = Ns.literal("1d");
    const before = Ns.literal("-1d1h");
    try t.expectEqual(@as(i128, -2), try before.ratioFloor(day));
    try t.expect((try before.mod(day)).eql(Ns.literal("23h")));
}

test "A3 a duration negates and takes its length, refusing the minimum" {
    const D = aegis.units.Duration(.second, i8);
    try t.expect((try D.fromRaw(5).negate()).eql(.fromRaw(-5)));
    try t.expect((try D.fromRaw(-127).negate()).eql(.fromRaw(127)));
    try t.expectError(error.Overflow, D.fromRaw(-128).negate());
    try t.expect((try D.fromRaw(-7).abs()).eql(.fromRaw(7)));
    try t.expect((try D.fromRaw(7).abs()).eql(.fromRaw(7)));
    try t.expectError(error.Overflow, D.fromRaw(-128).abs());
}

test "A3 a ranged value widens into any integer or duration that holds its whole range, with no error" {
    const Hour = aegis.int.Ranged(u8, 0, 23);
    try t.expectEqual(@as(u5, 23), Hour.literal(23).widen(u5));
    try t.expectEqual(@as(i64, 7), Hour.literal(7).widen(i64));
    const Offset = aegis.int.Ranged(i32, -86_399, 86_399);
    try t.expectEqual(@as(i18, -86_399), Offset.literal(-86_399).widen(i18));
    const hours = aegis.units.Duration(.hour, i64).fromRanged(Hour.literal(5));
    try t.expect(hours.eql(.literal("5h")));
    const offset = aegis.units.Duration(.second, i32).fromRanged(Offset.literal(-3600));
    try t.expect(offset.eql(.literal("-1h")));
    // A narrower duration than Ranged's representation, which holds the range.
    try t.expect(aegis.units.Duration(.hour, u8).fromRanged(aegis.int.Ranged(i64, 0, 23).literal(9)).eql(.fromRaw(9)));
}

test "A3 an instant is its span since the clock's zero, both ways with no error, at i128 across Temporal's bounds" {
    const Ns = aegis.units.Duration(.nanosecond, i128);
    const At = aegis.units.Instant(.real, .nanosecond, i128);
    try t.expect(At.epoch.sinceEpoch().eql(.fromRaw(0)));
    // Temporal's instants lie within 10^8 days of the epoch, and a time duration within 2^53 seconds.
    const limit = Ns.literal("100000000d");
    const max_time = try (try Ns.literal("1s").mul(1 << 53)).sub(.fromRaw(1));
    for ([_]Ns{ limit, try limit.negate() }) |edge| {
        const instant = At.fromSinceEpoch(edge);
        try t.expect(instant.sinceEpoch().eql(edge));
        const later = try instant.add(max_time);
        const earlier = try instant.sub(max_time);
        try t.expect((try earlier.durationTo(later)).eql(try max_time.mul(2)));
        try t.expect((try later.sinceEpoch().sub(max_time)).eql(edge));
        // Whole days and the nanoseconds of the day past them, as a calendar reads an instant.
        const day = Ns.literal("1d");
        const days = try earlier.sinceEpoch().ratioFloor(day);
        const of_day = try earlier.sinceEpoch().mod(day);
        try t.expect((try (try day.mul(days)).add(of_day)).eql(earlier.sinceEpoch()));
        try t.expect(of_day.compare(.fromRaw(0)) != .lt and of_day.compare(day) == .lt);
    }
}

test "A3 a duration reads as fractional seconds, the nearest float where its count is exact" {
    const U = aegis.units;
    const Ms = U.Duration(.millisecond, i64);
    // An interface that takes a CFTimeInterval: the decimal's own f64.
    try t.expectEqual(@as(f64, 0.25), Ms.fromRaw(250).toSeconds(f64));
    try t.expectEqual(@as(f64, 1.5), Ms.fromRaw(1500).toSeconds(f64));
    try t.expectEqual(@as(f64, 0.001), Ms.fromRaw(1).toSeconds(f64));
    try t.expectEqual(@as(f64, -0.25), Ms.fromRaw(-250).toSeconds(f64));
    try t.expectEqual(@as(f32, 0.25), Ms.fromRaw(250).toSeconds(f32));
    try t.expectEqual(@as(f64, 120.0), U.Duration(.minute, u8).fromRaw(2).toSeconds(f64));
    try t.expectEqual(@as(f64, 172_800.0), U.Duration(.day, i32).fromRaw(2).toSeconds(f64));
    try t.expectEqual(@as(f64, 0.0), U.Duration(.second, u8).fromRaw(0).toSeconds(f64));
    try t.expectEqual(@as(f128, 0.000_000_001), U.Duration(.nanosecond, i64).fromRaw(1).toSeconds(f128));
    // The longest nanosecond span an i64 holds is finite in every float from f32 up.
    const longest = U.Duration(.nanosecond, i64).fromRaw(std.math.maxInt(i64));
    try t.expectEqual(@as(f64, 9_223_372_036.854_775_807), longest.toSeconds(f64));
    try t.expect(std.math.isFinite(longest.toSeconds(f32)));
    try t.expect(std.math.isFinite(U.Duration(.day, i128).fromRaw(std.math.maxInt(i128)).toSeconds(f64)));
    // An f16 is reached through f32, so a millisecond step is no step of its own; past its range is an infinity.
    try t.expectEqual(@as(f16, 0.25), Ms.fromRaw(250).toSeconds(f16));
    try t.expectEqual(@as(f16, 0.001), Ms.fromRaw(1).toSeconds(f16));
    try t.expect(std.math.isPositiveInf(U.Duration(.day, i32).fromRaw(1).toSeconds(f16)));
    try t.expect(std.math.isNegativeInf(U.Duration(.day, i32).fromRaw(-1).toSeconds(f16)));
}

test "A3 a duration is a C timespec: whole seconds toward negative infinity and the nanoseconds past them, checked where seconds may not fit" {
    const U = aegis.units;
    const Ms = U.Duration(.millisecond, i64);
    // POSIX's where the target has one; on Windows `std.posix.timespec` is `std.c.timespec`, whose
    // fields are void, so a struct of its shape stands in and one contract holds on every target.
    const posix = std.posix.timespec;
    const Ts = if (@typeInfo(posix) == .@"struct" and @typeInfo(@FieldType(posix, "sec")) == .int) posix else extern struct { sec: isize, nsec: isize };
    // nanosleep's argument: 1.5s.
    const a = try Ms.fromRaw(1500).toTimespec(Ts);
    try t.expectEqual(@as(@FieldType(Ts, "sec"), 1), a.sec);
    try t.expectEqual(@as(@FieldType(Ts, "nsec"), 500_000_000), a.nsec);
    // A negative span keeps nsec in 0..999_999_999, as POSIX does.
    const b = try Ms.fromRaw(-1).toTimespec(Ts);
    try t.expectEqual(@as(@FieldType(Ts, "sec"), -1), b.sec);
    try t.expectEqual(@as(@FieldType(Ts, "nsec"), 999_000_000), b.nsec);
    const Wide = struct { sec: i64, nsec: i64 };
    // A whole unit has no nanoseconds; a nanosecond count is all nanoseconds under a second.
    try t.expectEqual(Wide{ .sec = 120, .nsec = 0 }, U.Duration(.minute, u8).fromRaw(2).toTimespec(Wide));
    try t.expectEqual(Wide{ .sec = 0, .nsec = 255 }, U.Duration(.nanosecond, u8).fromRaw(255).toTimespec(Wide));
    try t.expectEqual(Wide{ .sec = 9_223_372_036, .nsec = 854_775_807 }, U.Duration(.nanosecond, i64).fromRaw(std.math.maxInt(i64)).toTimespec(Wide));
    try t.expectEqual(Wide{ .sec = -9_223_372_037, .nsec = 145_224_192 }, U.Duration(.nanosecond, i64).fromRaw(std.math.minInt(i64)).toTimespec(Wide));
    // No error where every span fits: a 32-bit millisecond count into a 64-bit sec.
    comptime std.debug.assert(@TypeOf(U.Duration(.millisecond, i32).fromRaw(1).toTimespec(Wide)) == Wide);
    // An isize or c_long sec counts as 32 bits, so a millisecond i64 may overflow on some target; a narrow
    // sec does here.
    comptime std.debug.assert(Ms.ToTimespecError(Ts) == error{Overflow});
    comptime std.debug.assert(Ms.ToTimespecError(struct { sec: c_long, nsec: c_long }) == error{Overflow});
    const Narrow = struct { sec: i8, nsec: i32 };
    try t.expectEqual(Narrow{ .sec = 127, .nsec = 999_000_000 }, try Ms.fromRaw(127_999).toTimespec(Narrow));
    try t.expectError(error.Overflow, Ms.fromRaw(128_000).toTimespec(Narrow));
    try t.expectEqual(Narrow{ .sec = -128, .nsec = 0 }, try Ms.fromRaw(-128_000).toTimespec(Narrow));
    try t.expectError(error.Overflow, Ms.fromRaw(-128_001).toTimespec(Narrow));
    // An unsigned sec refuses a negative span.
    try t.expectError(error.Overflow, Ms.fromRaw(-1).toTimespec(struct { sec: u32, nsec: u32 }));
}

test "A3 a count's remainder by a plain divisor, as a round robin takes its slot, refusing zero" {
    const U = aegis.units;
    const Turn = U.Count(struct {}, u32);
    // A turn of three servers.
    try t.expectEqual(@as(u32, 0), (try Turn.fromRaw(6).rem(3)).raw());
    try t.expectEqual(@as(u32, 1), (try Turn.fromRaw(7).rem(3)).raw());
    try t.expectEqual(@as(u32, 0), (try Turn.fromRaw(std.math.maxInt(u32)).rem(3)).raw()); // 2^32 - 1 is a multiple of 3
    try t.expectEqual(@as(u32, 3), (try Turn.fromRaw(std.math.maxInt(u32)).rem(4)).raw());
    try t.expectError(error.DivisionByZero, Turn.fromRaw(7).rem(0));
    comptime std.debug.assert(Turn.RemError == error{DivisionByZero});
    // Signed: the count's sign, as @rem; the minimum by -1 is zero, never an overflow.
    const S = U.Count(struct {}, i8);
    try t.expectEqual(@as(i8, -1), (try S.fromRaw(-7).rem(3)).raw());
    try t.expectEqual(@as(i8, 1), (try S.fromRaw(7).rem(-3)).raw());
    try t.expectEqual(@as(i8, 0), (try S.fromRaw(-128).rem(-1)).raw());
    var x: i16 = -128;
    while (x <= 127) : (x += 1) {
        for ([_]i8{ -128, -3, -1, 1, 2, 7, 127 }) |d| {
            try t.expectEqual(@as(i8, @intCast(@rem(x, d))), (try S.fromRaw(@intCast(x)).rem(d)).raw());
        }
    }
}

test "A3 an instant floors to the start of its tick, toward negative infinity, saturating at the minimum" {
    const U = aegis.units;
    const Real = U.Instant(.real, .second, i8);
    const tick = U.Duration(.second, i8).fromRaw(2);
    // On a boundary an instant is its tick's start; just past, it goes back to it.
    try t.expectEqual(@as(i8, 4), Real.fromRaw(4).floor(tick).raw());
    try t.expectEqual(@as(i8, 4), Real.fromRaw(5).floor(tick).raw());
    try t.expectEqual(@as(i8, 0), Real.fromRaw(0).floor(tick).raw());
    try t.expectEqual(@as(i8, 0), Real.fromRaw(1).floor(tick).raw());
    // Before zero the tick holding it starts earlier, not at zero.
    try t.expectEqual(@as(i8, -2), Real.fromRaw(-1).floor(tick).raw());
    try t.expectEqual(@as(i8, -2), Real.fromRaw(-2).floor(tick).raw());
    try t.expectEqual(@as(i8, -4), Real.fromRaw(-3).floor(tick).raw());
    // The extremes: the largest stays inside, and a start before the smallest saturates at it.
    try t.expectEqual(@as(i8, 126), Real.fromRaw(127).floor(tick).raw());
    try t.expectEqual(@as(i8, -128), Real.fromRaw(-128).floor(tick).raw());
    try t.expectEqual(@as(i8, -128), Real.fromRaw(-128).floor(U.Duration(.second, i8).fromRaw(3)).raw());
    try t.expectEqual(@as(i8, -126), Real.fromRaw(-126).floor(U.Duration(.second, i8).fromRaw(3)).raw());
    try t.expectEqual(@as(i8, -127), Real.fromRaw(-1).floor(U.Duration(.second, i8).fromRaw(127)).raw());
    try t.expectEqual(@as(i8, -128), Real.fromRaw(-128).floor(U.Duration(.second, i8).fromRaw(127)).raw());
    try t.expectEqual(@as(i8, 0), Real.fromRaw(126).floor(U.Duration(.second, i8).fromRaw(127)).raw());
    try t.expectEqual(@as(i8, 127), Real.fromRaw(127).floor(U.Duration(.second, i8).fromRaw(127)).raw());
    // A tick of one step is every instant's own.
    try t.expectEqual(@as(i8, -7), Real.fromRaw(-7).floor(U.Duration(.second, i8).fromRaw(1)).raw());
    // Unsigned: never below zero, so nothing to saturate.
    const Mono = U.Instant(.awake, .millisecond, u8);
    try t.expectEqual(@as(u8, 250), Mono.fromRaw(255).floor(U.Duration(.millisecond, u8).fromRaw(10)).raw());
    try t.expectEqual(@as(u8, 0), Mono.fromRaw(9).floor(U.Duration(.millisecond, u8).fromRaw(10)).raw());
    // Exhaustive against a wider oracle.
    for ([_]i8{ 1, 2, 3, 5, 7, 64, 127 }) |step| {
        var x: i16 = -128;
        while (x <= 127) : (x += 1) {
            const oracle = @max(@divFloor(x, step) * step, -128);
            try t.expectEqual(@as(i8, @intCast(oracle)), Real.fromRaw(@intCast(x)).floor(U.Duration(.second, i8).fromRaw(step)).raw());
        }
    }
}

test "A3 scalar layout and all-build scalar contracts" {
    inline for (.{ u8, i32, u64, usize, i128 }) |R| {
        inline for (.{ aegis.int.Checked(R), aegis.int.Saturating(R), aegis.int.Ranged(R, 0, 1), aegis.id.Id(struct {}, R), aegis.units.Duration(.second, R), aegis.units.Instant(struct {}, .second, R), aegis.units.Bytes(R) }) |T| {
            try t.expectEqual(@sizeOf(R), @sizeOf(T));
            try t.expectEqual(@alignOf(R), @alignOf(T));
        }
    }
    aegis.assert.invariant(true, "test invariant");
    aegis.assert.maybe(false);
    aegis.assert.maybe(true);
    var hits: aegis.assert.Coverage = .{};
    aegis.assert.maybeCount(false, &hits);
    aegis.assert.maybeCount(true, &hits);
    if (builtin.is_test) {
        try t.expectEqual(@as(usize, 1), hits.yes);
        try t.expectEqual(@as(usize, 1), hits.no);
    }
}

const shake = @import("shakedown");
test "A3 wide arithmetic and unit conversions shakedown properties" {
    try shake.check(t.allocator, {}, wideProperty, .{ .cases = 2048, .seed = 0xa3 });
}
fn wideProperty(_: void, case: *shake.Case) anyerror!void {
    const a = shake.gen.int(case.source, i64);
    const b = shake.gen.int(case.source, i64);
    const product: i128 = @as(i128, a) * b;
    const actual = aegis.int.Checked(i64).init(a).mul(b);
    if (product < std.math.minInt(i64)) try t.expectError(error.Underflow, actual) else if (product > std.math.maxInt(i64)) try t.expectError(error.Overflow, actual) else try t.expectEqual(product, @as(i128, (try actual).raw()));
    const nanos = shake.gen.int(case.source, i64);
    const q = @divFloor(nanos, 1000);
    const r = @mod(nanos, 1000);
    const D = aegis.units.Duration(.nanosecond, i64);
    try t.expectEqual(q, D.fromRaw(nanos).convert(.microsecond, i64, .down).raw());
    try t.expectEqual(q + @intFromBool(r != 0), D.fromRaw(nanos).convert(.microsecond, i64, .up).raw());
    if (r != 0) try t.expectError(error.Inexact, D.fromRaw(nanos).convert(.microsecond, i64, .exact));
    const count = shake.gen.int(case.source, u64);
    const bits = aegis.units.Bits(u64).fromRaw(count);
    try t.expectEqual(count / 8 + @intFromBool(count % 8 != 0), (try bits.toBytesRounded(.up)).raw());
}

test "A3 fake clock step suspend and epoch conversion" {
    var clock: shake.Clock = .init(t.io, .{});
    const io = clock.io();
    const U = aegis.units;
    const A = U.Instant(.awake, .nanosecond, i128);
    const B = U.Instant(.boot, .nanosecond, i128);
    const R = U.Instant(.real, .nanosecond, i128);
    const a = try A.fromIoTimestamp(.now(io, .awake), .exact);
    const b = try B.fromIoTimestamp(.now(io, .boot), .exact);
    clock.advance(.fromNanoseconds(7));
    clock.suspendFor(.fromNanoseconds(11));
    try t.expectEqual(@as(i96, 7), (try a.durationTo(try A.fromIoTimestamp(.now(io, .awake), .exact))).raw());
    try t.expectEqual(@as(i96, 18), (try b.durationTo(try B.fromIoTimestamp(.now(io, .boot), .exact))).raw());
    clock.stepReal(.fromNanoseconds(-99));
    try t.expectEqual(@as(i96, -99), (try R.fromIoTimestamp(.now(io, .real), .exact)).raw());
}

test "A3 one-bit arithmetic" {
    try t.expectError(error.Overflow, aegis.int.Checked(u1).init(1).add(1));
    try t.expectEqual(@as(u1, 1), (try aegis.int.Checked(u1).init(1).shl(0)).raw());
    try t.expectEqual(u0, std.math.Log2Int(u1));
}

test "A3 shifts encodings and side effects" {
    inline for (.{ u8, i8 }) |R| {
        var a: i32 = std.math.minInt(R);
        while (a <= std.math.maxInt(R)) : (a += 1) {
            const x: R = @intCast(a); // safe: loop traverses R's domain
            for (0..8) |shift| {
                const expected: i32 = @as(i32, a) * (@as(i32, 1) << @as(u3, @intCast(shift))); // safe: range is 0..8
                const got = aegis.int.Checked(R).init(x).shl(@intCast(shift)); // safe: range is 0..8
                if (got) |v| {
                    if (expected < std.math.minInt(R) or expected > std.math.maxInt(R)) {
                        return error.ShiftOverflowAccepted;
                    }
                    try t.expectEqual(expected, @as(i32, v.raw()));
                } else |err| {
                    if (expected < std.math.minInt(R)) try t.expectEqual(error.Underflow, err) else if (expected > std.math.maxInt(R)) try t.expectEqual(error.Overflow, err) else return err;
                }
                try t.expectEqual(std.math.clamp(expected, std.math.minInt(R), std.math.maxInt(R)), @as(i32, aegis.int.Saturating(R).init(x).shl(@intCast(shift)).raw()));
            }
        }
    }
    const D = aegis.units.Duration(.second, i16);
    const d = D.fromRaw(-258);
    try t.expectEqual(@as(i16, -258), D.decode(d.encode(.big), .big).raw());
    try t.expectEqualSlices(u8, &.{ 0xfe, 0xfe }, &d.encode(.big));
    const R = aegis.int.Ranged(u8, 1, 10);
    try t.expectError(error.OutOfRange, R.fromBytes(.{0}, .big));
    try t.expectError(error.InvalidId, aegis.id.NonZero(struct {}, u8).fromBytes(.{0}, .little));
    var evaluated: usize = 0;
    aegis.assert.invariant(evaluate(&evaluated), "predicate exactly once");
    try t.expectEqual(@as(usize, 1), evaluated);
    aegis.assert.debugCheck(evaluate, &evaluated);
    try t.expectEqual(@as(usize, if (builtin.optimize == .debug) 2 else 1), evaluated);
}
fn evaluate(n: *usize) bool {
    n.* += 1;
    return true;
}
