//! Every supported scalar repr/factory, independent raw integer/extreme/endian oracle.
const std = @import("std");
const a = @import("../root.zig");
const t = std.testing;
const Tag = struct {};
test "A3 enum factories preserve extremes imports and serialization" {
    @setEvalBranchQuota(2000000);
    inline for (.{ u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, usize, isize }) |R| {
        inline for (.{ a.id.Id(Tag, R), a.id.NonZero(Tag, R), a.units.Count(Tag, R), a.units.Bytes(R), a.units.Bits(R), a.units.Duration(.second, R), a.units.Instant(.awake, .second, R), a.int.Ranged(R, std.math.minInt(R), std.math.maxInt(R)) }) |T| {
            try t.expect(@typeInfo(T) == .@"enum");
            try t.expectEqual(std.lang.Type.Enum.Mode.nonexhaustive, @typeInfo(T).@"enum".mode);
            try t.expectEqual(@sizeOf(R), @sizeOf(T));
            try t.expectEqual(@alignOf(R), @alignOf(T));
            for ([_]R{ std.math.minInt(R), std.math.maxInt(R), 1 }) |raw| {
                if (T == a.id.NonZero(Tag, R) and raw == 0) continue;
                const value: T = if (T == a.int.Ranged(R, std.math.minInt(R), std.math.maxInt(R))) try T.init(raw) else if (T == a.id.NonZero(Tag, R)) try T.fromRaw(raw) else T.fromRaw(raw);
                try t.expectEqual(raw, value.raw());
                inline for (.{ .little, .big }) |endian| {
                    var expected: [@sizeOf(R)]u8 = undefined;
                    std.mem.writeInt(R, &expected, raw, endian);
                    const encoded = if (@hasDecl(T, "encode")) value.encode(endian) else value.toBytes(endian);
                    try t.expectEqualSlices(u8, &expected, &encoded);
                    const decoded: T = if (@hasDecl(T, "decode")) T.decode(expected, endian) else if (T == a.id.NonZero(Tag, R) or T == a.int.Ranged(R, std.math.minInt(R), std.math.maxInt(R))) try T.fromBytes(expected, endian) else T.fromBytes(expected, endian);
                    try t.expectEqual(raw, decoded.raw());
                }
            }
        }
        try t.expectError(error.InvalidId, a.id.NonZero(Tag, R).fromRaw(0));
        try t.expectError(error.InvalidId, a.id.NonZero(Tag, R).fromBytes(@splat(0), .big));
        const Range = a.int.Ranged(R, 1, 2);
        try t.expectError(error.OutOfRange, Range.init(0));
        try t.expectError(error.OutOfRange, Range.init(std.math.maxInt(R)));
        try t.expectError(error.OutOfRange, Range.fromBytes(@splat(0), .little));
        if (comptime @typeInfo(R).int.signedness == .signed) {
            try t.expectError(error.OutOfRange, Range.init(std.math.minInt(R)));
            try t.expectError(error.Overflow, a.units.Duration(.second, R).fromRaw(-1).convert(.second, u128, .exact));
        } else {
            const C = a.id.Counter(Tag, R);
            try t.expect(@typeInfo(C) == .@"enum");
            var counter = C.init(std.math.maxInt(R) - 1);
            try t.expectEqual(std.math.maxInt(R), (try counter.next()).raw());
            try t.expectError(error.IdExhausted, counter.next());
            try t.expectEqual(std.math.maxInt(R), @backingInt(counter));
        }
    }
}
