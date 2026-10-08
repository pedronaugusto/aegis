const a = @import("aegis");
export fn bad() void {
    _ = a.int.cast(u64, @as(f32, 1));
}
