const std = @import("std");
const aegis = @import("aegis");
pub fn main() !void {
    var secret = aegis.Secret([32]u8).init(@splat(0));
    defer secret.deinit();
    var allocated = try aegis.SecretBytes.init(std.heap.page_allocator, 64);
    defer allocated.deinit();
    try allocated.replace("consumer fixture");
    try allocated.reserve(96);
    var shared = aegis.Guarded(u64).init(0);
    var held = shared.acquire();
    defer held.deinit();
    held.value().* += secret.expose()[0];
    const n = try aegis.int.Checked(usize).init(7).mul(9);
    const id = aegis.id.Id(struct {}, u64).fromRaw(n.raw());
    const bytes = try aegis.units.Bits(u64).fromRaw(id.raw()).toBytesRounded(.up);
    aegis.assert.invariant(bytes.raw() == 8, "checked byte conversion");
}
