const std = @import("std");
const aegis = @import("aegis");
pub fn main() !void {
    var owned_secret = aegis.Secret([32]u8).init(@splat(0));
    defer owned_secret.deinit();
    var allocated = try aegis.SecretBytes.init(std.heap.page_allocator, 64);
    defer allocated.deinit();
    try allocated.replace("consumer fixture");
    try allocated.reserve(96);
    var shared = aegis.Guarded(u64).init(0);
    var held = shared.acquire();
    defer held.deinit();
    held.value().* += owned_secret.expose()[0];
    const n = try aegis.int.Checked(usize).init(7).mul(9);
    const identifier = aegis.id.Id(struct {}, u64).fromRaw(n.raw());
    const bytes = try aegis.units.Bits(u64).fromRaw(identifier.raw()).toBytesRounded(.up);
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

const secret = @import("aegis.secret");
const sync = @import("aegis.sync");
const id = @import("aegis.id");
const units = @import("aegis.units");
const int = @import("aegis.int");
const assert = @import("aegis.assert");
const handle = @import("aegis.handle");
const input = @import("aegis.input");
const err = @import("aegis.err");
const bounded = @import("aegis.bounded");
const own = @import("aegis.own");
comptime {
    std.debug.assert(aegis.Secret == secret.Secret);
    std.debug.assert(aegis.SecretBytes == secret.SecretBytes);
    std.debug.assert(aegis.secret.Choice == secret.Choice);
    std.debug.assert(aegis.Guarded == sync.Guarded);
    std.debug.assert(aegis.BlockingGuarded == sync.BlockingGuarded);
    std.debug.assert(aegis.RwGuarded == sync.RwGuarded);
    std.debug.assert(aegis.Condition == sync.Condition);
    std.debug.assert(aegis.Once == sync.Once);
    std.debug.assert(aegis.InitContext == sync.InitContext);
    std.debug.assert(aegis.Lazy == sync.Lazy);
    std.debug.assert(aegis.Shared == sync.Shared);
    std.debug.assert(aegis.Order == sync.Order);
    std.debug.assert(aegis.Confined == sync.Confined);
    std.debug.assert(aegis.TaskIdentity == sync.TaskIdentity);
    std.debug.assert(aegis.bounded.Array == bounded.Array);
    std.debug.assert(aegis.own.Owned == own.Owned);
    std.debug.assert(aegis.id.Id == id.Id);
    std.debug.assert(aegis.units.Bytes == units.Bytes);
    std.debug.assert(aegis.int.Checked == int.Checked);
    std.debug.assert(aegis.assert.invariant == assert.invariant);
    std.debug.assert(aegis.handle.Pool == handle.Pool);
    std.debug.assert(aegis.input.Untrusted == input.Untrusted);
    std.debug.assert(aegis.err.Context == err.Context);
}
