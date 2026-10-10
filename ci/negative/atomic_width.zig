const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.Atomic(a.units.Duration(.nanosecond, i96)));
}
