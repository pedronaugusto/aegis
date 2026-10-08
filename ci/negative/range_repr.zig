const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.int.Ranged(u24, 0, 1));
}
