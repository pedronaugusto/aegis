const std = @import("std");
const e = @import("err.zig");
const t = std.testing;
const Frame = struct {
    pub const aegis_public_frame = true;
    phase: enum { record, certificate },
    offset: u32,
    reason: enum { bad_length, canceled },
};
const C = e.Context(Frame, 2);
test "A9 inline contexts preserve first frames cause and independent copies" {
    var failure: e.Failure(error{ BadLength, Canceled }, Frame, 2) = .{ .cause = error.BadLength };
    failure.context.push(.{ .phase = .record, .offset = 3, .reason = .bad_length });
    failure.context.push(.{ .phase = .certificate, .offset = 4, .reason = .bad_length });
    failure.context.push(.{ .phase = .certificate, .offset = 5, .reason = .canceled });
    try t.expect(failure.context.truncated);
    try t.expectEqual(@as(usize, 2), failure.context.frames().len);
    try t.expectEqual(@as(u32, 3), failure.context.frames()[0].offset);
    var copy = failure;
    failure.context.reset();
    try t.expectEqual(@as(usize, 2), copy.context.frames().len);
    try t.expectEqual(error.BadLength, copy.cause);
    var storage: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    try copy.context.format(&writer);
    try t.expectEqualStrings("phase=0 offset=3 reason=0\nphase=1 offset=4 reason=0\n[truncated]", writer.buffered());
    var tiny = std.Io.Writer.fixed(&.{});
    try t.expectError(error.WriteFailed, copy.context.format(&tiny));
    try t.expectEqual(@as(usize, 2), copy.context.frames().len);
    copy.context.reset();
    try t.expect(!copy.context.truncated);
    var zero: e.Context(Frame, 0) = .{};
    zero.push(.{ .phase = .record, .offset = 0, .reason = .canceled });
    try t.expect(zero.truncated and zero.frames().len == 0);
}
test "A9 classified text escapes complete bytes with bounded storage" {
    const text = e.PublicText(8).copy(.classify("a\n\x80z", "public protocol label"));
    try t.expectEqualStrings("a\\x0a", text.view());
    try t.expect(text.truncated);
    const label = e.PublicText(16).literal("safe\"\\");
    try t.expectEqualStrings("safe\\x22\\x5c", label.view());
    const TextFrame = struct {
        pub const aegis_public_frame = true;
        label: e.PublicText(16),
    };
    var context: e.Context(TextFrame, 1) = .{};
    context.push(.{ .label = label });
    var bytes: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try context.format(&writer);
    try t.expectEqualStrings("label=safe\\x22\\x5c", writer.buffered());
}
