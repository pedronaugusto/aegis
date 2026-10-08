const std = @import("std");
const a = @import("aegis");
export fn shift(x: u8, n: usize) u32 {
    const result = a.int.Checked(u8).init(x).shl(n) catch |err| return if (err == error.Overflow) 1000 else 2000;
    return result.raw();
}
test "A3 isolated u8 release shift error channel" {
    try std.testing.expectEqual(@as(u32, 1000), shift(128, 1));
    try std.testing.expectEqual(@as(u32, 254), shift(127, 1));
}

test "A3 exhaustive isolated checked shift" {
    var x: u16 = 0;
    while (x < 256) : (x += 1) {
        for (0..8) |n| {
            const v: u8 = @intCast(x); // safe: loop is 0..256
            const expected = @as(u32, x) << @as(u5, @intCast(n)); // safe: n is 0..8
            const result = a.int.Checked(u8).init(v).shl(n);
            if (result) |got| {
                if (expected > 255) return error.AcceptedOverflow;
                try std.testing.expectEqual(expected, @as(u32, got.raw()));
            } else |err| {
                if (expected > 255) try std.testing.expectEqual(error.Overflow, err) else return err;
            }
        }
    }
}

test "A3 loop with saturating shift" {
    inline for (.{ u8, i8 }) |R| {
        var x: i32 = std.math.minInt(R);
        while (x <= std.math.maxInt(R)) : (x += 1) {
            for (0..8) |n| {
                const v: R = @intCast(x); // safe: representation bounds
                const expected = x * (@as(i32, 1) << @as(u3, @intCast(n))); // safe: n is 0..8
                const result = a.int.Checked(R).init(v).shl(n);
                if (result) |got| {
                    if (expected < std.math.minInt(R) or expected > std.math.maxInt(R)) return error.AcceptedOverflow;
                    try std.testing.expectEqual(expected, @as(i32, got.raw()));
                } else |err| {
                    if (expected < std.math.minInt(R)) try std.testing.expectEqual(error.Underflow, err) else if (expected > std.math.maxInt(R)) try std.testing.expectEqual(error.Overflow, err) else return err;
                }
                const sat = try a.int.Saturating(R).init(v).shl(n);
                try std.testing.expectEqual(std.math.clamp(expected, std.math.minInt(R), std.math.maxInt(R)), @as(i32, sat.raw()));
            }
        }
    }
}

test "A3 signed loop checked shift only" {
    inline for (.{ u8, i8 }) |R| {
        var x: i32 = std.math.minInt(R);
        while (x <= std.math.maxInt(R)) : (x += 1) {
            for (0..8) |n| {
                const v: R = @intCast(x); // safe: representation bounds
                const expected = x * (@as(i32, 1) << @as(u3, @intCast(n))); // safe: n is 0..8
                const result = a.int.Checked(R).init(v).shl(n);
                if (result) |got| {
                    if (expected < std.math.minInt(R) or expected > std.math.maxInt(R)) return error.AcceptedOverflow;
                    try std.testing.expectEqual(expected, @as(i32, got.raw()));
                } else |err| {
                    if (expected < std.math.minInt(R)) try std.testing.expectEqual(error.Underflow, err) else if (expected > std.math.maxInt(R)) try std.testing.expectEqual(error.Overflow, err) else return err;
                }
            }
        }
    }
}

test "A3 plain raw checked shift same loop" {
    inline for (.{ u8, i8 }) |R| {
        var x: i32 = std.math.minInt(R);
        while (x <= std.math.maxInt(R)) : (x += 1) {
            for (0..8) |n| {
                const v: R = @intCast(x); // safe: representation bounds
                const expected = x * (@as(i32, 1) << @as(u3, @intCast(n))); // safe: n is 0..8
                const result = rawShift(R, v, n);
                if (result) |got| {
                    if (expected < std.math.minInt(R) or expected > std.math.maxInt(R)) return error.AcceptedOverflow;
                    try std.testing.expectEqual(expected, @as(i32, got));
                } else |err| {
                    if (expected < std.math.minInt(R)) try std.testing.expectEqual(error.Underflow, err) else if (expected > std.math.maxInt(R)) try std.testing.expectEqual(error.Overflow, err) else return err;
                }
            }
        }
    }
}

inline fn rawShift(comptime R: type, value: R, n: usize) error{ InvalidShift, Overflow, Underflow }!R {
    if (n >= @bitSizeOf(R)) return error.InvalidShift;
    const amount: std.math.Log2Int(R) = @intCast(n); // safe: preceding width check
    if (value > @as(R, std.math.maxInt(R)) >> amount) return error.Overflow;
    if (value < @as(R, std.math.minInt(R)) >> amount) return error.Underflow;
    return value << amount;
}
