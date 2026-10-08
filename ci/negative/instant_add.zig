const a = @import("aegis");
const A = a.units.Instant(.awake, .second, i64);
export fn bad() void {
    _ = A.fromRaw(1).add(A.fromRaw(2));
}
