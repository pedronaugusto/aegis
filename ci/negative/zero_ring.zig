const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.bounded.Ring(u64, 0));
}
