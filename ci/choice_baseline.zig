//! Independent handwritten equivalent byte-mask baseline with the same checks/barriers.
const std = @import("std");
pub inline fn barrier(comptime T: type, v: T) T {
    return asm volatile (""
        : [out] "=r" (-> T),
        : [in] "0" (v),
    );
}
pub const Bit = packed struct(u1) { value: u1 };
pub inline fn bit(v: u32) Bit {
    return .{ .value = @truncate(barrier(u32, v)) }; // safe: callers establish a one-bit kernel invariant
}
pub inline fn equal(a: []const u8, b: []const u8) error{LengthMismatch}!Bit {
    @setRuntimeSafety(true);
    if (a.len != b.len) return error.LengthMismatch;
    const x: [*]const volatile u8 = a.ptr;
    const y: [*]const volatile u8 = b.ptr;
    var acc: u32 = 0;
    for (0..a.len) |i| acc |= x[i] ^ y[i];
    return bit(((barrier(u32, acc) -% 1) >> 8) & 1);
}
pub inline fn order(comptime N: usize, endian: std.lang.Endian, a: *const [N]u8, b: *const [N]u8) struct { lt: Bit, eq: Bit, gt: Bit } {
    @setRuntimeSafety(true);
    const x: *const volatile [N]u8 = a;
    const y: *const volatile [N]u8 = b;
    var eq: u32 = 1;
    var lt: u32 = 0;
    var gt: u32 = 0;
    for (0..N) |j| {
        const i = if (endian == .big) j else N - 1 - j;
        const av: u32 = x[i];
        const bv: u32 = y[i];
        lt |= (((av -% bv) >> 8) & 1) & eq;
        gt |= (((bv -% av) >> 8) & 1) & eq;
        eq &= (((av ^ bv) -% 1) >> 8) & 1;
    }
    return .{ .lt = bit(lt), .eq = bit(eq), .gt = bit(gt) };
}
pub inline fn selectInt(comptime T: type, choice: Bit, a: T, b: T) T {
    const unsigned = @Int(.unsigned, @bitSizeOf(T));
    const register = if (@bitSizeOf(T) == 64) u64 else u32;
    const mask = barrier(register, 0 -% @as(register, choice.value));
    const inverse = barrier(register, ~mask);
    const x: unsigned = @bitCast(a); // safe: same-width integer representation
    const y: unsigned = @bitCast(b); // safe: same-width integer representation
    const v: unsigned = @truncate((@as(register, x) & inverse) | (@as(register, y) & mask)); // safe: retain T's width
    return @bitCast(v); // safe: every T bit pattern is valid
}
pub inline fn selectBytes(comptime N: usize, choice: Bit, out: *[N]u8, a: *const [N]u8, b: *const [N]u8) error{PartialOverlap}!void {
    @setRuntimeSafety(true);
    const d = @intFromPtr(out); // safe: public live address validation
    const xaddr = @intFromPtr(a); // safe: public live address
    const yaddr = @intFromPtr(b); // safe: public live address
    if (overlap(N, d, xaddr) or overlap(N, d, yaddr)) return error.PartialOverlap;
    const mask = barrier(u32, 0 -% @as(u32, choice.value));
    const inverse = barrier(u32, ~mask);
    const x: *const volatile [N]u8 = a;
    const y: *const volatile [N]u8 = b;
    for (0..N) |i| {
        const av = x[i];
        const bv = y[i];
        out[i] = @truncate((@as(u32, av) & inverse) | (@as(u32, bv) & mask));
    } // safe: byte result
}
inline fn overlap(comptime N: usize, a: usize, b: usize) bool {
    if (a == b or N == 0) return false;
    return if (a > b) a - b < N else b - a < N;
}
