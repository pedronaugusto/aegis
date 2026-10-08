const a = @import("aegis");
export fn bad() void {
    _ = a.units.Bytes(u64).fromRaw(1).add(a.units.Bits(u64).fromRaw(1));
}
