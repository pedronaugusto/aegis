const std = @import("std");
const aegis = @import("aegis");
export fn denied(gpa: *const std.mem.Allocator) void {
    var secret = aegis.SecretBytes.init(gpa.*, 32) catch @panic("allocation failure");
    defer secret.deinit();
    var output: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    writer.print("{f}", .{secret}) catch return;
}
