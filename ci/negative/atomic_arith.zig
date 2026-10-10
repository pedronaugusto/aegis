const a = @import("aegis");
export fn bad() u32 {
    var cell: a.Atomic(a.id.Id(struct {}, u32)) = .init(.fromRaw(1));
    return (cell.fetchAdd(.fromRaw(1), .monotonic) catch return 0).raw();
}
