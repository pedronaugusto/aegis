const aegis = @import("aegis");

pub fn main() !void {
    // --- README:usage ---
    var key = aegis.Secret([32]u8).init(@splat(7));
    defer key.deinit();
    const bytes = key.expose(); // borrow ends at cleanup/transfer
    var counts = aegis.Guarded(usize).init(0);
    var held = counts.acquire();
    defer held.deinit();
    held.value().* += bytes[0];
    const Request = aegis.id.NonZero(struct {}, u64);
    const request = try Request.fromRaw(1);
    const size = try aegis.int.Checked(usize).init(4).mul(8);
    const payload = aegis.units.Bytes(usize).fromRaw(size.raw());
    const timeout = aegis.units.Duration(.millisecond, i64).fromRaw(250).toIoDuration();
    aegis.assert.post(payload.raw() == 32, "payload fits the record");
    _ = request;
    _ = timeout;
    // --- README:usage ---
}
