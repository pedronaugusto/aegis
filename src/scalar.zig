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
