const std = @import("std");
const s = @import("../root.zig").secret;
const t = std.testing;
fn reveal(c: s.Choice) bool {
    return c.declassify("test oracle verdict");
}

test "A5 all imported bits and logical truth tables" {
    try t.expectEqual(@as(usize, 1), @sizeOf(s.Choice));
    try t.expectEqual(@as(usize, 1), @bitSizeOf(s.Choice));
    for (0..256) |i| {
        const bit: u8 = @intCast(i); // safe: exhaustive byte domain
        if (i > 1) {
            try t.expectError(error.InvalidBit, s.Choice.fromBit(bit));
            continue;
        }
        const a = try s.Choice.fromBit(bit);
        const copied = a;
        try t.expectEqual(i == 1, reveal(copied));
        try t.expectEqual(i == 0, reveal(a.not()));
        for (0..2) |j| {
            const b = try s.Choice.fromBit(@intCast(j)); // safe: public 0/1
            try t.expectEqual(i == 1 and j == 1, reveal(a.@"and"(b)));
            try t.expectEqual(i == 1 or j == 1, reveal(a.@"or"(b)));
            try t.expectEqual(i != j, reveal(a.xor(b)));
        }
    }
}
test "A5 exhaustive byte equality order and select independent oracle" {
    for (0..256) |i| for (0..256) |j| {
        const a: [1]u8 = .{@intCast(i)}; // safe: byte-domain loop
        const b: [1]u8 = .{@intCast(j)}; // safe: byte-domain loop
        const eq = s.equal(1, &a, &b);
        try t.expectEqual(i == j, reveal(eq));
        inline for (.{ .big, .little }) |endian| {
            const o = s.compareUnsigned(1, endian, &a, &b);
            try t.expectEqual(i < j, reveal(o.lt));
            try t.expectEqual(i == j, reveal(o.eq));
            try t.expectEqual(i > j, reveal(o.gt));
        }
        try t.expectEqual(if (i == j) b[0] else a[0], eq.selectInt(u8, a[0], b[0]));
    };
}
test "A5 public length empty and every mismatch position" {
    const empty: [0]u8 = .{};
    try t.expect(reveal(s.equal(0, &empty, &empty)));
    const order = s.compareUnsigned(0, .little, &empty, &empty);
    try t.expect(reveal(order.eq));
    try t.expect(!reveal(order.lt) and !reveal(order.gt));
    var a: [64]u8 = @splat(0);
    var b = a;
    try t.expectError(error.LengthMismatch, s.equalBytes(&a, b[0..63]));
    try t.expectError(error.LengthMismatch, s.equalBytes(&empty, &b));
    for (0..64) |i| {
        b[i] = 255;
        try t.expect(!reveal(s.equal(64, &a, &b)));
        try t.expect(!reveal(try s.equalBytes(&a, &b)));
        b[i] = 0;
    }
}
test "A5 multi-byte endian order primary reference and adversarial classes" {
    var prng = std.Random.DefaultPrng.init(0xa5a5);
    const r = prng.random();
    for (0..4000) |i| {
        var a: [32]u8 = undefined;
        var b: [32]u8 = undefined;
        r.bytes(&a);
        r.bytes(&b);
        if (i % 4 == 0) b = a;
        if (i % 4 == 1) {
            a = @splat(0);
            b = @splat(255);
        }
        if (i % 4 == 2) {
            b = a;
            b[i % 32] ^= 0x80;
        }
        try t.expectEqual(std.mem.eql(u8, &a, &b), reveal(s.equal(32, &a, &b)));
        inline for (.{ .big, .little }) |endian| {
            const expected = std.crypto.timing_safe.compare(u8, &a, &b, endian);
            const o = s.compareUnsigned(32, endian, &a, &b);
            try t.expectEqual(expected == .lt, reveal(o.lt));
            try t.expectEqual(expected == .eq, reveal(o.eq));
            try t.expectEqual(expected == .gt, reveal(o.gt));
            const x = std.mem.readInt(u256, &a, endian);
            const y = std.mem.readInt(u256, &b, endian);
            try t.expectEqual(x < y, reveal(o.lt));
        }
    }
}
test "A5 integer widths signed extrema and aliases with public overlap rejection" {
    inline for (.{ u8, i8, u16, i16, u32, i32, u64, i64 }) |T| {
        const a = std.math.minInt(T);
        const b = std.math.maxInt(T);
        try t.expectEqual(a, (try s.Choice.fromBit(0)).selectInt(T, a, b));
        try t.expectEqual(b, (try s.Choice.fromBit(1)).selectInt(T, a, b));
    }
    var storage: [65]u8 = @splat(0x55);
    var b: [32]u8 = @splat(0xaa);
    const a: *[32]u8 = storage[0..32];
    const partial: *[32]u8 = storage[1..33];
    const before = storage;
    try t.expectError(error.PartialOverlap, (try s.Choice.fromBit(1)).selectBytes(32, partial, a, &b));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectError(error.PartialOverlap, (try s.Choice.fromBit(0)).selectBytes(32, a, partial, &b));
    var out: [32]u8 = undefined;
    try (try s.Choice.fromBit(0)).selectBytes(32, &out, a, &b);
    try t.expectEqualSlices(u8, a, &out);
    try (try s.Choice.fromBit(1)).selectBytes(32, a, a, &b);
    try t.expectEqualSlices(u8, &b, a);
    a.* = @splat(0x11);
    try (try s.Choice.fromBit(0)).selectBytes(32, &b, a, &b);
    try t.expectEqualSlices(u8, a, &b);
    var empty: [0]u8 = .{};
    try (try s.Choice.fromBit(1)).selectBytes(0, &empty, &empty, &empty);
}
test "A5 generated properties shrink through shakedown" {
    const shake = @import("shakedown");
    try shake.check(t.allocator, {}, struct {
        fn property(_: void, c: *shake.Case) !void {
            const a = shake.gen.int(c.source, u64);
            const b = shake.gen.int(c.source, u64);
            const x = std.mem.toBytes(a);
            const y = std.mem.toBytes(b);
            const eq = s.equal(8, &x, &y);
            try t.expectEqual(a == b, reveal(eq));
            try t.expectEqual(if (a == b) b else a, eq.selectInt(u64, a, b));
        }
    }.property, .{ .cases = 1024, .seed = 0xa5 });
}
