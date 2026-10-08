const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.int.Ranged(u8, 3, 1));
}
