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
    var domain = aegis.handle.Domain.init(0x1234);
    const Pool = aegis.handle.Pool(u32, struct {});
    var slots: [1]Pool.Slot = undefined;
    var pool = try Pool.initBuffer(&slots, try domain.issue());
    defer pool.deinit(ignore);
    var item: u32 = 5;
    const key = try pool.insert(&item);
    try pool.remove(key, &item);
    const parsed = try aegis.input.Untrusted([]const u8).init(&.{5}).parse({}, parse);
    var diagnostics: aegis.err.Context(Frame, 1) = .{};
    diagnostics.push(.{ .offset = parsed.value });
    var buffer: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try diagnostics.format(&writer);
}

fn ignore(_: *u32) void {}
const Parsed = struct { value: u8 };
fn parse(_: void, bytes: []const u8) error{Truncated}!Parsed {
    if (bytes.len != 1) return error.Truncated;
    return .{ .value = bytes[0] };
}
const Frame = struct {
    pub const aegis_public_frame = true;
    offset: u8,
};
