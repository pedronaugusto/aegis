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
    try t.expectError(error.InvalidShift, C.init(1).shl(-1));
    try t.expectError(error.InvalidShift, C.init(1).shl(8));
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

test "A3 scalar layout and all-build scalar contracts" {
    inline for (.{ u8, i32, u64, usize, i128 }) |R| {
        inline for (.{ aegis.int.Checked(R), aegis.int.Saturating(R), aegis.int.Ranged(R, 0, 1), aegis.id.Id(struct {}, R), aegis.units.Duration(.second, R), aegis.units.Instant(struct {}, .second, R), aegis.units.Bytes(R) }) |T| {
            try t.expectEqual(@sizeOf(R), @sizeOf(T));
            try t.expectEqual(@alignOf(R), @alignOf(T));
        }
    }
    aegis.assert.invariant(true, "test invariant");
    aegis.assert.pre(true, "test pre");
    aegis.assert.post(true, "test post");
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
    try t.expectError(error.InvalidShift, aegis.int.Checked(u1).init(1).shl(1));
}

test "A3 shifts encodings and side effects" {
    inline for (.{ u8, i8 }) |R| {
        var a: i32 = std.math.minInt(R);
        while (a <= std.math.maxInt(R)) : (a += 1) {
            const x: R = @intCast(a); // safe: loop traverses R's domain
            for (0..8) |shift| {
                const expected: i32 = @as(i32, a) * (@as(i32, 1) << @as(u3, @intCast(shift))); // safe: range is 0..8
                const got = aegis.int.Checked(R).init(x).shl(shift);
                if (got) |v| {
                    if (expected < std.math.minInt(R) or expected > std.math.maxInt(R)) {
                        return error.ShiftOverflowAccepted;
                    }
                    try t.expectEqual(expected, @as(i32, v.raw()));
                } else |err| {
                    if (expected < std.math.minInt(R)) try t.expectEqual(error.Underflow, err) else if (expected > std.math.maxInt(R)) try t.expectEqual(error.Overflow, err) else return err;
                }
                try t.expectEqual(std.math.clamp(expected, std.math.minInt(R), std.math.maxInt(R)), @as(i32, (try aegis.int.Saturating(R).init(x).shl(shift)).raw()));
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
    aegis.assert.pre(evaluate(&evaluated), "predicate exactly once");
    try t.expectEqual(@as(usize, 1), evaluated);
    aegis.assert.debugCheck(evaluate, &evaluated);
    try t.expectEqual(@as(usize, if (builtin.optimize == .debug) 2 else 1), evaluated);
}
fn evaluate(n: *usize) bool {
    n.* += 1;
    return true;
}
