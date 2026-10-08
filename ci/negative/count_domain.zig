const a = @import("aegis");
const A = a.units.Count(struct {}, u64);
const B = a.units.Count(struct {}, u64);
export fn bad() void {
    _ = A.fromRaw(1).add(B.fromRaw(1));
}
