//! Immutable published proof seam: cloak c1 wire/Der.Reader.next + single.
//! https://github.com/pedronaugusto/cloak/blob/3a66309c49ab024be4e2647c9c3da4550e740ac0/src/wire/Der.zig
//! This fixture retains the envelope checks, not certificate grammar or authentication.
const std = @import("std");
const a = @import("../root.zig");
const t = std.testing;
const DerError = error{ InvalidDer, DerLimit };
const Element = struct { tag: u8, encoded: []const u8, value: []const u8 };
const Diagnostic = struct {
    pub const aegis_public_frame = true;
    phase: enum { certificate },
    reason: enum { invalid_der, der_limit },
    offset: usize,
};
const Context = a.err.Context(Diagnostic, 2);
const Options = struct { tag: u8, limit: usize, diagnostics: ?*Context = null };
fn envelope(options: Options, bytes: []const u8) DerError!Element {
    return single(options, bytes) catch |cause| {
        if (options.diagnostics) |ctx| ctx.push(.{ .phase = .certificate, .offset = 0, .reason = if (cause == error.DerLimit) .der_limit else .invalid_der });
        return cause;
    };
}
fn single(options: Options, bytes: []const u8) DerError!Element {
    if (bytes.len > options.limit) return error.DerLimit;
    if (bytes.len < 2) return error.InvalidDer;
    const tag = bytes[0];
    if (tag & 0x1f == 0x1f or tag == 0 or tag != options.tag) return error.InvalidDer;
    var cursor: usize = 2;
    const first = bytes[1];
    var len: usize = first;
    if (first & 0x80 != 0) {
        const count: usize = first & 0x7f;
        if (count == 0 or count > @sizeOf(usize) or count > bytes.len - cursor) return error.InvalidDer;
        if (bytes[cursor] == 0) return error.InvalidDer;
        len = 0;
        for (bytes[cursor..][0..count]) |b| len = (len << 8) | b;
        cursor += count;
        if (len < 128) return error.InvalidDer;
    }
    if (len != bytes.len - cursor) return error.InvalidDer;
    return .{ .tag = tag, .encoded = bytes, .value = bytes[cursor..] };
}
test "A9 published cloak DER envelope retains length canonicality and public diagnostics" {
    var context: Context = .{};
    const options: Options = .{ .tag = 0x30, .limit = 256, .diagnostics = &context };
    const parser = a.input.Untrusted([]const u8);
    const empty = try parser.init(&.{ 0x30, 0 }).parse(options, envelope);
    try t.expectEqual(@as(usize, 0), empty.value.len);
    const invalid = [_][]const u8{
        &.{},                   &.{0x30},                  &.{ 0x30, 0, 0 }, &.{ 0x31, 0 },    &.{ 0x30, 0x80 },
        &.{ 0x30, 0x81, 1, 0 }, &.{ 0x30, 0x82, 0, 0x80 }, &.{ 0x30, 0x89 }, &.{ 0x30, 2, 1 }, &.{ 0x30, 0x88, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
    };
    for (invalid) |bytes| try t.expectError(error.InvalidDer, parser.init(bytes).parse(options, envelope));
    try t.expect(context.truncated and context.frames().len == 2);
    var canonical: [131]u8 = @splat(0);
    canonical[0] = 0x30;
    canonical[1] = 0x81;
    canonical[2] = 0x80;
    const parsed = try parser.init(&canonical).parse(options, envelope);
    try t.expectEqual(@as(usize, 128), parsed.value.len);
    try t.expectError(error.DerLimit, parser.init(&canonical).parse(Options{ .tag = 0x30, .limit = 130 }, envelope));
}
fn fuzzEnvelope(_: void, smith: *t.Smith) !void {
    var bytes: [512]u8 = undefined;
    const n = smith.slice(&bytes);
    if (a.input.Untrusted([]const u8).init(bytes[0..n]).parse(Options{ .tag = 0x30, .limit = 256 }, envelope)) |element| {
        try t.expect(element.encoded.len <= 256 and element.tag == 0x30);
        try t.expect(element.value.len <= element.encoded.len - 2);
    } else |cause| try t.expect(cause == error.InvalidDer or cause == error.DerLimit);
}
test "A9 published DER boundary fuzz target" {
    try t.fuzz({}, fuzzEnvelope, .{});
}
const WorkTag = struct {};
const Completion = struct { request: u64, done: bool = false };
fn ignoreCompletion(_: *Completion) void {}
test "A8 signing completion fixture rejects late stale work and independent instances" {
    var domain = a.handle.Domain.init(0xc103);
    const Map = a.handle.SlotMap(Completion, WorkTag);
    var work = try Map.init(t.allocator, try domain.issue(), .{ .capacity = 1 });
    defer work.deinit(ignoreCompletion);
    var other = try Map.init(t.allocator, try domain.issue(), .{ .capacity = 1 });
    defer other.deinit(ignoreCompletion);
    var request: Completion = .{ .request = 12 };
    const late_event = try work.insert(&request);
    try work.remove(late_event, &request);
    const current = try work.insert(&request);
    try t.expectError(error.InvalidKey, work.get(late_event));
    try t.expectError(error.InvalidKey, other.get(current));
    (try work.get(current)).done = true;
    try t.expect((try work.get(current)).done);
}
