//! Representation kernels; no public runtime metadata.
const std = @import("std");
pub fn integer(comptime T: type) void {
    if (@typeInfo(T) != .int or @typeInfo(T).int.bits == 0)
        @compileError("aegis requires a nonzero-width integer representation");
}
/// Enum representation widths; 128-bit values are supported in Zig, not promised C ABI types.
pub fn abiInteger(comptime T: type) void {
    integer(T);
    switch (@bitSizeOf(T)) {
        8, 16, 32, 64, 128 => {},
        else => @compileError("aegis ABI scalar requires an 8/16/32/64/128-bit integer representation"),
    }
}
/// Clock and duration widths: any whole number of bytes up to 128 bits, which takes in std's i96
/// nanoseconds. Like the 128-bit widths, not a C ABI promise.
pub fn wholeByteInteger(comptime T: type) void {
    integer(T);
    const bits = @typeInfo(T).int.bits;
    if (bits % 8 != 0 or bits > 128)
        @compileError("aegis clock and duration requires a whole-byte integer representation of at most 128 bits");
}
/// Whether every `Source` value converts to `Target` on every target aegis supports. `usize` and `isize` are 32 to
/// 64 bits wide there, so they count as the widest they are as a source and the narrowest as a target: `u32` to
/// `usize` and `usize` to `u64` cannot fail, `u64` to `usize` can, and code correct on one target compiles on all.
/// Spelled in one body, without helper calls, because comptime calls draw on the caller's evaluation quota.
pub fn lossless(comptime Source: type, comptime Target: type) bool {
    if (Source == Target) return true;
    const source_min = if (Source == isize) std.math.minInt(i64) else std.math.minInt(Source);
    const source_max = if (Source == usize) std.math.maxInt(u64) else if (Source == isize) std.math.maxInt(i64) else std.math.maxInt(Source);
    const target_min = if (Target == isize) std.math.minInt(i32) else std.math.minInt(Target);
    const target_max = if (Target == usize) std.math.maxInt(u32) else if (Target == isize) std.math.maxInt(i32) else std.math.maxInt(Target);
    return source_min >= target_min and source_max <= target_max;
}
pub fn Bytes(comptime R: type) type {
    integer(R);
    if (@bitSizeOf(R) % 8 != 0) @compileError("encoding requires a whole-byte representation");
    return [@bitSizeOf(R) / 8]u8;
}
pub fn encode(comptime R: type, value: R, endian: std.builtin.Endian) Bytes(R) {
    var out: Bytes(R) = undefined;
    std.mem.writeInt(R, &out, value, endian);
    return out;
}
pub fn decode(comptime R: type, value: Bytes(R), endian: std.builtin.Endian) R {
    return std.mem.readInt(R, &value, endian);
}
