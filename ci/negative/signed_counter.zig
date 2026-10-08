const a = @import("aegis");
export fn bad() usize {
    return @sizeOf(a.id.Counter(struct {}, i64));
}
