const a = @import("aegis");
export fn bad() i32 {
    const next = a.id.Id(struct {}, i32).fromRaw(1).successor() catch return 0;
    return next.raw();
}
