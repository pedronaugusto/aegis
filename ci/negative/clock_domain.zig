const a = @import("aegis");
const A = a.units.Instant(.awake, .second, i64);
const B = a.units.Instant(.real, .second, i64);
export fn bad() void {
    _ = A.fromRaw(1).durationTo(B.fromRaw(1));
}
