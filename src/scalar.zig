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
