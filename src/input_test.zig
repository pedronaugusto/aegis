const std = @import("std");
const input = @import("root.zig").input;
const t = std.testing;
const Header = struct { body: []const u8, kind: u8 };
const ParseError = error{ Truncated, LimitExceeded, Canceled };
fn parse(limit: usize, bytes: []const u8) ParseError!Header {
    if (bytes.len < 2) return error.Truncated;
    if (bytes[1] > limit) return error.LimitExceeded;
    if (bytes.len - 2 < bytes[1]) return error.Truncated;
    return .{ .kind = bytes[0], .body = bytes[2..][0..bytes[1]] };
}
test "A9 input parser boundaries retain exact checks refined type and const view" {
    var bytes = [_]u8{ 7, 2, 30, 31 };
    const marker = input.Untrusted([]u8).init(&bytes);
    try t.expect(@TypeOf(marker.readForParse()) == []const u8);
    const header = try marker.parse(@as(usize, 2), parse);
    try t.expectEqual(@as(u8, 7), header.kind);
    try t.expectEqualSlices(u8, &.{ 30, 31 }, header.body);
    try t.expectError(error.LimitExceeded, marker.parse(@as(usize, 1), parse));
    try t.expectError(error.Truncated, input.Untrusted([]const u8).init(bytes[0..3]).parse(@as(usize, 2), parse));
    bytes[2] = 42; // Borrowed refinement does not freeze mutable input.
    try t.expectEqual(@as(u8, 42), header.body[0]);
    const pointer = input.Untrusted(*u8).init(&bytes[0]);
    try t.expect(@TypeOf(pointer.readForParse()) == *const u8);
}
fn fuzzParse(bytes: []const u8) !void {
    const result = input.Untrusted([]const u8).init(bytes).parse(@as(usize, 16), parse);
    if (result) |header| {
        try t.expect(bytes.len >= 2 and bytes[1] <= 16 and bytes[1] <= bytes.len - 2);
        try t.expectEqual(@as(usize, bytes[1]), header.body.len);
    } else |cause| try t.expect(cause == error.Truncated or cause == error.LimitExceeded);
}
test "A9 parser boundary fuzz target" {
    try t.fuzz({}, struct {
        fn run(_: void, smith: *std.testing.Smith) anyerror!void {
            var buf: [256]u8 = undefined;
            const n = smith.slice(&buf);
            try fuzzParse(buf[0..n]);
        }
    }.run, .{});
}
const Parsed = struct {
    allocation: []u8,
    gpa: std.mem.Allocator,
    fn deinit(self: *Parsed) void {
        self.gpa.free(self.allocation);
        self.* = undefined;
    }
};
const Ctx = struct { gpa: std.mem.Allocator, fail: bool, cancel: bool };
fn acquiring(ctx: Ctx, bytes: []const u8) (std.mem.Allocator.Error || ParseError)!Parsed {
    const allocation = try ctx.gpa.dupe(u8, bytes);
    errdefer ctx.gpa.free(allocation);
    if (ctx.cancel) return error.Canceled;
    if (ctx.fail) return error.Truncated;
    return .{ .gpa = ctx.gpa, .allocation = allocation };
}
test "A9 parser error and cancellation release acquired resources and retain input" {
    const bytes = "public-schema";
    const marker = input.Untrusted([]const u8).init(bytes);
    try t.expectError(error.Truncated, marker.parse(Ctx{ .gpa = t.allocator, .fail = true, .cancel = false }, acquiring));
    try t.expectError(error.Canceled, marker.parse(Ctx{ .gpa = t.allocator, .fail = false, .cancel = true }, acquiring));
    var parsed = try marker.parse(Ctx{ .gpa = t.allocator, .fail = false, .cancel = false }, acquiring);
    defer parsed.deinit();
    try t.expectEqualStrings(bytes, parsed.allocation);
}
