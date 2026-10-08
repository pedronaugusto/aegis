const a = @import("aegis");
const std = @import("std");
comptime {
    for (.{ u8, i16, u32, i64, u128, usize }) |R| {
        for (.{ a.int.Checked(R), a.int.Saturating(R), a.int.Ranged(R, 0, 1), a.id.Id(struct {}, R), a.id.NonZero(struct {}, R), a.units.Count(struct {}, R), a.units.Bytes(R), a.units.Bits(R), a.units.Duration(.second, R), a.units.Instant(struct {}, .second, R) }) |T| {
            if (@sizeOf(T) != @sizeOf(R) or @alignOf(T) != @alignOf(R)) @compileError("scalar layout changed");
        }
    }
    if ((a.int.Checked(usize).init(std.math.maxInt(usize)).add(1)) != error.Overflow) @compileError("usize overflow accepted");
}
export fn checked(a_raw: usize, b: usize) usize {
    return (a.int.Checked(usize).init(a_raw).add(b) catch return 0).raw();
}
export fn unit(a_raw: i64) i64 {
    return (a.units.Duration(.nanosecond, i64).fromRaw(a_raw).convert(.microsecond, i64, .down) catch return 0).raw();
}
