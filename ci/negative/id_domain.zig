const a = @import("aegis");
const A = a.id.Id(struct {}, u64);
const B = a.id.Id(struct {}, u64);
export fn bad() bool {
    return A.fromRaw(1).eql(B.fromRaw(1));
}
