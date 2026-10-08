const std = @import("std");
const aegis = @import("aegis");
export fn format() void {
    var secret = aegis.Secret([32]u8).init(@splat(0));
    defer secret.deinit();
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    writer.print("{f}", .{&secret}) catch return;
}
