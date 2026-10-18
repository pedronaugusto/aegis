const std = @import("std");
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
    aegis.assert.post(payload.eql(.fromRaw(32)), "payload fits the record");
    // One text form for durations and sizes, exact both ways: `1m30s`, `64MiB`.
    const grace = try aegis.units.Duration(.millisecond, u32).parse("1m30s");
    const limit = try aegis.units.Bytes(u64).parse("64MiB");
    var line: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&line);
    try w.print("grace {f}, limit {f}", .{ grace, limit });
    aegis.assert.post(std.mem.eql(u8, w.buffered(), "grace 1m30s, limit 64MiB"), "text reads back");
    _ = request;
    _ = timeout;
    // --- README:usage ---
}
