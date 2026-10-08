const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.units.Duration(.nanosecond, i96));
}
