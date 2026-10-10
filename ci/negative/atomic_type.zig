const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.Atomic(u32));
}
