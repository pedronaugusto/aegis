//! Non-elidable A3 caller workloads paired with independent checked baselines.
const std = @import("std");
const a = @import("aegis");
const Tag = struct {};
pub const names = .{ "add", "sub", "mul", "div", "rem", "shift", "saturating", "ranged", "cast", "identity", "counter", "count", "bits", "duration", "rounding", "instant", "invariant", "diagnostics", "encoding" };
pub fn operation(comptime name: []const u8, comptime wrapped: bool, x: u64, y: u64) u64 {
    if (comptime std.mem.eql(u8, name, "add") or std.mem.eql(u8, name, "count")) {
        if (wrapped) {
            if (comptime std.mem.eql(u8, name, "count")) return (a.units.Count(Tag, u64).fromRaw(x).add(.fromRaw(y)) catch return 0).raw();
            return (a.int.Checked(u64).init(x).add(y) catch return 0).raw();
        }
        const v = @addWithOverflow(x, y);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "sub")) {
        if (wrapped) return (a.int.Checked(u64).init(x).sub(y) catch return 0).raw();
        const v = @subWithOverflow(x, y);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "mul")) {
        if (wrapped) return (a.int.Checked(u64).init(x).mul(y) catch return 0).raw();
        const v = @mulWithOverflow(x, y);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "div")) {
        const sx: i64 = @bitCast(x); // safe: every input bit pattern denotes an i64
        const sy: i64 = @bitCast(y); // safe: every input bit pattern denotes an i64
        if (wrapped) return @bitCast((a.int.Checked(i64).init(sx).div(sy) catch return 0).raw()); // safe: preserve signed representation
        if (sy == 0 or (sx == std.math.minInt(i64) and sy == -1)) return 0;
        return @bitCast(@divTrunc(sx, sy)); // safe: preserve signed representation
    }
    if (comptime std.mem.eql(u8, name, "rem")) {
        const sx: i64 = @bitCast(x); // safe: every input bit pattern denotes an i64
        const sy: i64 = @bitCast(y); // safe: every input bit pattern denotes an i64
        if (wrapped) return @bitCast((a.int.Checked(i64).init(sx).rem(sy) catch return 0).raw()); // safe: preserve signed representation
        if (sy == 0 or sy == -1) return 0;
        return @bitCast(@rem(sx, sy)); // safe: preserve signed representation
    }
    if (comptime std.mem.eql(u8, name, "shift")) {
        if (wrapped) return (a.int.Checked(u64).init(x).shl(y) catch return 0).raw();
        if (y >= 64) return 0;
        const n: u6 = @intCast(y); // safe: preceding y < 64 check
        const result = @as(u128, x) << n;
        if (result > std.math.maxInt(u64)) return 0;
        return @intCast(result); // safe: target-bound check
    }
    if (comptime std.mem.eql(u8, name, "saturating")) {
        if (wrapped) return a.int.Saturating(u64).init(x).mul(y).add(x).raw();
        return (x *| y) +| x;
    }
    if (comptime std.mem.eql(u8, name, "ranged")) {
        if (wrapped) return ((a.int.Ranged(u64, 1, 10000).init(x) catch return 0).add(y) catch return 0).raw();
        if (x < 1 or x > 10000) return 0;
        const v = @addWithOverflow(x, y);
        if (v[1] != 0 or v[0] < 1 or v[0] > 10000) return 0;
        return v[0];
    }
    if (comptime std.mem.eql(u8, name, "cast")) {
        if (wrapped) return a.int.cast(u32, x) catch return 0;
        return directCast(x) catch return 0;
    }
    if (comptime std.mem.eql(u8, name, "identity")) {
        if (wrapped) return @intFromBool(a.id.Id(Tag, u64).fromRaw(x).eql(.fromRaw(y)));
        return @intFromBool(x == y);
    }
    if (comptime std.mem.eql(u8, name, "counter")) {
        if (wrapped) {
            var c = a.id.Counter(Tag, u64).init(x);
            return (c.next() catch return 0).raw();
        }
        const v = @addWithOverflow(x, 1);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "bits")) {
        if (wrapped) return (a.units.Bits(u64).fromRaw(x).toBytesRounded(.up) catch return 0).raw();
        return x / 8 + @intFromBool(x % 8 != 0);
    }
    if (comptime std.mem.eql(u8, name, "duration")) {
        if (wrapped) return (a.units.Duration(.millisecond, u64).fromRaw(x).convert(.nanosecond, u64, .exact) catch return 0).raw();
        const v = @mulWithOverflow(x, 1000000);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "rounding")) {
        const sx: i64 = @bitCast(x); // safe: every input bit pattern denotes an i64
        if (wrapped) return @bitCast((a.units.Duration(.nanosecond, i64).fromRaw(sx).convert(.microsecond, i64, .down) catch return 0).raw()); // safe: preserve signed representation
        return @bitCast(@divFloor(sx, 1000)); // safe: preserve signed representation
    }
    if (comptime std.mem.eql(u8, name, "instant")) {
        if (wrapped) return (a.units.Instant(.awake, .nanosecond, u64).fromRaw(x).add(a.units.Duration(.nanosecond, u64).fromRaw(y)) catch return 0).raw();
        const v = @addWithOverflow(x, y);
        return if (v[1] != 0) 0 else v[0];
    }
    if (comptime std.mem.eql(u8, name, "invariant")) {
        // Successful caller path contains the same conditional fail-stop.
        if (wrapped) a.assert.invariant(x <= y, "a3 bounded caller") else if (x > y) @panic("a3 bounded caller");
        return y - x;
    }
    if (comptime std.mem.eql(u8, name, "diagnostics")) {
        if (wrapped) {
            a.assert.debugCheck(predicate, x);
            a.assert.maybe(x == y);
            var coverage: a.assert.Coverage = .{};
            a.assert.maybeCount(x == y, &coverage);
        }
        return x ^ y;
    }
    if (comptime std.mem.eql(u8, name, "encoding")) {
        var bytes: [8]u8 = undefined;
        if (wrapped) bytes = a.id.Id(Tag, u64).fromRaw(x).toBytes(.big) else std.mem.writeInt(u64, &bytes, x, .big);
        return std.mem.readInt(u64, &bytes, .little);
    }
    @compileError("unknown numeric workload");
}
fn predicate(_: u64) bool {
    return true;
}

inline fn directCast(x: u64) error{Overflow}!u32 {
    if (x > std.math.maxInt(u32)) return error.Overflow;
    return @intCast(x); // safe: explicit target-range check
}
