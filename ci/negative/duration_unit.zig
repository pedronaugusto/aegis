const a = @import("aegis");
export fn bad() void {
    _ = a.units.Duration(.second, u64).fromRaw(1).add(a.units.Duration(.millisecond, u64).fromRaw(1));
}
