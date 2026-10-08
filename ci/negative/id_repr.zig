const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.id.Id(struct {}, u3));
}
