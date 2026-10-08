const std = @import("std");
const Secret = @import("Secret.zig").Secret;
const Material = @import("material").Material;

fn erased(bytes: []const u8) !void {
    // Never print material, even on a failed regression.
    for (bytes) |byte| try std.testing.expect(byte == 0);
}

fn wipePattern(comptime T: type, pattern: u8) !void {
    var owner: Secret(T) = undefined;
    const bytes = std.mem.asBytes(&owner);
    @memset(bytes, pattern);
    owner.deinit();
    try erased(bytes);
}

test "Secret full inline erasure includes aggregate and Material padding" {
    const Padded = extern struct { flag: u8, word: u64 };
    try wipePattern([32]u8, 0x51);
    try wipePattern([48]u8, 0xa7);
    try wipePattern(Padded, 0x6d);
    try wipePattern(Material, 0x9b);
}

test "Secret transfer preserves representation and wipes source and destination" {
    var owner: Secret(Material) = undefined;
    var destination: Secret(Material) = undefined;
    @memset(std.mem.asBytes(&owner), 0xd3);
    owner.moveInto(&destination);
    try erased(std.mem.asBytes(&owner));
    for (std.mem.asBytes(&destination)) |byte| try std.testing.expect(byte == 0xd3);
    destination.deinit();
    try erased(std.mem.asBytes(&destination));
}

test "Secret explicit const and mutable exposure" {
    var owner = Secret([32]u8).init(@splat(0x7b));
    defer owner.deinit();
    owner.exposeMut()[0] = 0x6c;
    try std.testing.expect(owner.expose()[0] == 0x6c);
    comptime try std.testing.expect(@TypeOf(owner.expose()) == *const [32]u8);
}

test "Secret formatting fails before writing content" {
    var owner = Secret([32]u8).init(@splat(0x4f));
    defer owner.deinit();
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.SecretNotFormattable, owner.format(&writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
}
