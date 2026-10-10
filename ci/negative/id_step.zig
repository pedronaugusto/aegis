const a = @import("aegis");
const Seq = a.id.Id(struct {}, u64);
export fn bad(seq: Seq) u64 {
    const moved = seq.advance(a.units.Bytes(u64).fromRaw(1)) catch return 0;
    return moved.raw();
}
