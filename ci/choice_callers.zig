//! A5 enclosing callers: real c1 byte/limb/table/padding shapes, plus later MAC verdict shape.
//! These are proof fixtures; no consumer adoption or curve arithmetic proof is implied.
const std = @import("std");
const s = @import("aegis").secret;
const base = @import("choice_baseline.zig");
pub const names = .{ "equal0", "equal1", "equal32", "equal48", "equal512", "dynamic", "order_big", "order_little", "order_runtime", "int8", "int16", "int32", "int64", "signed8", "signed16", "signed32", "signed64", "logic", "bytes", "alias", "montgomery", "curve", "offline", "finished", "dead" };
inline fn chosen(comptime wrapped: bool, a: *const [1]u8, b: *const [1]u8) if (wrapped) s.Choice else base.Bit {
    return if (wrapped) s.equal(1, a, b) else base.equal(a, b) catch unreachable; // unreachable: both fixed arrays have identical public lengths
}
inline fn equal(comptime wrapped: bool, comptime N: usize, a: *const [N]u8, b: *const [N]u8) u32 {
    return if (wrapped) @intFromBool(s.equal(N, a, b).declassify("fixture completed equality verdict")) else (base.equal(a, b) catch unreachable).value; // unreachable: both fixed arrays have identical public lengths
}
pub inline fn run(comptime name: []const u8, comptime wrapped: bool, out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: std.lang.Endian) u64 {
    @setRuntimeSafety(true);
    inline for (.{ 0, 1, 32, 48, 512 }) |N| {
        if (comptime std.mem.eql(u8, name, std.fmt.comptimePrint("equal{d}", .{N}))) return equal(wrapped, N, a[0..N], b[0..N]);
    }
    if (comptime std.mem.eql(u8, name, "dynamic")) {
        // Two independent public lengths packed only for the fixture ABI.
        const alen = len & 0xffff;
        const blen = len >> 16;
        if (alen > 512 or blen > 512) return 2;
        return if (wrapped) @intFromBool((s.equalBytes(a[0..alen], b[0..blen]) catch return 2).declassify("fixture dynamic verdict")) else (base.equal(a[0..alen], b[0..blen]) catch return 2).value;
    }
    if (comptime std.mem.startsWith(u8, name, "order_")) {
        const e = if (comptime std.mem.eql(u8, name, "order_big")) .big else if (comptime std.mem.eql(u8, name, "order_little")) .little else endian;
        const o = if (wrapped) s.compareUnsigned(32, e, a[0..32], b[0..32]) else base.order(32, e, a[0..32], b[0..32]);
        return if (wrapped) @as(u64, @intFromBool(o.lt.declassify("fixture order lt"))) | (@as(u64, @intFromBool(o.eq.declassify("fixture order eq"))) << 1) | (@as(u64, @intFromBool(o.gt.declassify("fixture order gt"))) << 2) else @as(u64, o.lt.value) | (@as(u64, o.eq.value) << 1) | (@as(u64, o.gt.value) << 2);
    }
    // These consumers form their own decisions; avoid a harness-only comparison.
    const c = if (comptime std.mem.eql(u8, name, "curve") or std.mem.eql(u8, name, "offline") or std.mem.eql(u8, name, "finished")) {} else chosen(wrapped, a[0..1], b[0..1]);
    inline for (.{ u8, u16, u32, u64 }) |T| {
        if (comptime std.mem.eql(u8, name, std.fmt.comptimePrint("int{d}", .{@bitSizeOf(T)}))) {
            const x = std.mem.readInt(T, a[0..@sizeOf(T)], .little);
            const y = std.mem.readInt(T, b[0..@sizeOf(T)], .little);
            return if (wrapped) c.selectInt(T, x, y) else base.selectInt(T, c, x, y);
        }
    }
    inline for (.{ i8, i16, i32, i64 }) |T| {
        if (comptime std.mem.eql(u8, name, std.fmt.comptimePrint("signed{d}", .{@bitSizeOf(T)}))) {
            const av = std.mem.readInt(T, a[0..@sizeOf(T)], .little);
            const bv = std.mem.readInt(T, b[0..@sizeOf(T)], .little);
            const value = if (wrapped) c.selectInt(T, av, bv) else base.selectInt(T, c, av, bv);
            return @as(@Int(.unsigned, @bitSizeOf(T)), @bitCast(value)); // safe: retain selected signed representation without a checked sign conversion
        }
    }
    if (comptime std.mem.eql(u8, name, "logic")) {
        const d = chosen(wrapped, a[1..2], b[1..2]);
        return if (wrapped) c.@"and"(d).@"or"(c.xor(d).not()).selectInt(u64, 7, 9) else base.selectInt(u64, base.bit(base.bit(c.value & d.value).value | base.bit(base.bit(c.value ^ d.value).value ^ 1).value), 7, 9);
    }
    if (comptime std.mem.eql(u8, name, "bytes") or std.mem.eql(u8, name, "alias")) {
        // Alias caller explicitly uses out as one source. Other partial overlaps stay errors.
        const source = if (comptime std.mem.eql(u8, name, "alias")) out[0..32] else a[0..32];
        if (wrapped) c.selectBytes(32, out[0..32], source, b[0..32]) catch return 2 else base.selectBytes(32, c, out[0..32], source, b[0..32]) catch return 2;
        return out[0];
    }
    if (comptime std.mem.eql(u8, name, "montgomery")) {
        // c1 Number is 128 u32 limbs; select all limbs then compare all 512 bytes.
        for (0..128) |i| {
            const x = std.mem.readInt(u32, a[i * 4 ..][0..4], .little);
            const y = std.mem.readInt(u32, b[i * 4 ..][0..4], .little);
            const z = if (wrapped) c.selectInt(u32, x, y) else base.selectInt(u32, c, x, y);
            std.mem.writeInt(u32, out[i * 4 ..][0..4], z, .little);
        }
        return equal(wrapped, 512, out, b);
    }
    if (comptime std.mem.eql(u8, name, "curve")) {
        // c1's fixed-window selection scans 1..15; secret digit never indexes table.
        @memset(out[0..32], 0);
        const digit: [1]u8 = .{a[0] & 15};
        inline for (1..16) |i| {
            const index: [1]u8 = .{i};
            const pick = chosen(wrapped, &digit, &index);
            // Existing c1 selection visits fixed table indices, then cMov coordinates.
            if (wrapped) pick.selectBytes(32, out[0..32], out[0..32], b[i * 32 ..][0..32]) catch return 2 else base.selectBytes(32, pick, out[0..32], out[0..32], b[i * 32 ..][0..32]) catch return 2;
        }
        return out[0];
    }
    if (comptime std.mem.eql(u8, name, "offline")) {
        // Full 16-byte c1 offline CBC padding accumulation before verdict release.
        const padding: [1]u8 = .{a[15]};
        const zero: [1]u8 = .{0};
        const limit: [1]u8 = .{16};
        if (wrapped) {
            var valid = s.equal(1, &padding, &zero).not().@"and"(s.compareUnsigned(1, .big, &padding, &limit).gt.not());
            for (0..16) |i| {
                const index: [1]u8 = .{@intCast(i)}; // safe: public 0..15
                const value: [1]u8 = .{a[15 - i]};
                valid = valid.@"and"(s.compareUnsigned(1, .big, &index, &padding).lt.not().@"or"(s.equal(1, &value, &padding)));
            }
            return @intFromBool(valid.declassify("completed offline CBC padding verdict"));
        } else {
            // unreachable: every equality compares two fixed one-byte arrays
            var valid = base.bit(base.bit((base.equal(&padding, &zero) catch unreachable).value ^ 1).value & base.bit(base.order(1, .big, &padding, &limit).gt.value ^ 1).value);
            for (0..16) |i| {
                const index: [1]u8 = .{@intCast(i)}; // safe: public 0..15
                const value: [1]u8 = .{a[15 - i]};
                // unreachable: both fixed one-byte arrays have identical public lengths
                valid = base.bit(valid.value & base.bit(base.bit(base.order(1, .big, &index, &padding).lt.value ^ 1).value | (base.equal(&value, &padding) catch unreachable).value).value);
            }
            return valid.value;
        }
    }
    if (comptime std.mem.eql(u8, name, "finished")) {
        // Future C2 proof shape only: full 48-byte MAC comparison then public verdict.
        if (equal(wrapped, 48, a[0..48], b[0..48]) == 0) return 0;
        return 1;
    }
    if (comptime std.mem.eql(u8, name, "dead")) {
        _ = chosen(wrapped, a[0..1], b[0..1]);
        if (wrapped) c.selectBytes(32, out[0..32], a[0..32], b[0..32]) catch return 2 else base.selectBytes(32, c, out[0..32], a[0..32], b[0..32]) catch return 2;
        return 0;
    }
    @compileError("unknown A5 caller");
}
