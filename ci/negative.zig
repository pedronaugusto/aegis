//! Negative compilation must fail for the intended shape-validation reason.
//! Each case is a whole program, written to the cache and compiled there: it
//! must never compile, so it is no source of the package.
const std = @import("std");

const Case = struct { name: []const u8, source: []const u8, message: []const u8 };

const cases = [_]Case{
    .{ .name = "slice", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret([]u8);
    \\}
    },
    .{ .name = "pointer", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(*u8);
    \\}
    },
    .{ .name = "aggregate", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(struct { bytes: [32]u8, pointer: *const u8 });
    \\}
    },
    .{ .name = "optional", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(?*u8);
    \\}
    },
    .{ .name = "union", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(union(enum) { bytes: [32]u8, pointer: *u8 });
    \\}
    },
    .{ .name = "function", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(*const fn () void);
    \\}
    },
    .{ .name = "nested", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret([2]struct { value: ?[]const u8 });
    \\}
    },
    .{ .name = "resource", .message = "Secret requires", .source =
    \\const aegis = @import("aegis");
    \\comptime {
    \\    _ = aegis.Secret(struct {
    \\        const Self = @This();
    \\        value: u64,
    \\        pub fn deinit(_: *Self) void {}
    \\    });
    \\}
    },
    .{ .name = "format", .message = "SecretNotFormattable", .source =
    \\const std = @import("std");
    \\const aegis = @import("aegis");
    \\export fn format() void {
    \\    var secret = aegis.Secret([32]u8).init(@splat(0));
    \\    defer secret.deinit();
    \\    var buffer: [128]u8 = undefined;
    \\    var writer = std.Io.Writer.fixed(&buffer);
    \\    writer.print("{f}", .{&secret}) catch return;
    \\}
    },
    .{ .name = "bytes_format", .message = "SecretNotFormattable", .source =
    \\const std = @import("std");
    \\const aegis = @import("aegis");
    \\export fn denied(gpa: *const std.mem.Allocator) void {
    \\    var secret = aegis.SecretBytes.init(gpa.*, 32) catch @panic("allocation failure");
    \\    defer secret.deinit(gpa.*);
    \\    var output: [128]u8 = undefined;
    \\    var writer = std.Io.Writer.fixed(&output);
    \\    writer.print("{f}", .{secret}) catch return;
    \\}
    },
    .{ .name = "order_cycle", .message = "cyclic lock order", .source =
    \\const a = @import("aegis");
    \\const O = a.Order(&.{ .{ .name = "one", .after = &.{1} }, .{ .name = "two", .after = &.{0} } });
    \\export fn bad() usize {
    \\    return @sizeOf(O.Context);
    \\}
    },
    .{ .name = "zero_ring", .message = "ring capacity must be nonzero", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.bounded.Ring(u64, 0));
    \\}
    },
    .{ .name = "id_domain", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\const A = a.id.Id(struct {}, u64);
    \\const B = a.id.Id(struct {}, u64);
    \\export fn bad() bool {
    \\    return A.fromRaw(1).eql(B.fromRaw(1));
    \\}
    },
    .{ .name = "count_domain", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\const A = a.units.Count(struct {}, u64);
    \\const B = a.units.Count(struct {}, u64);
    \\export fn bad() void {
    \\    _ = A.fromRaw(1).add(B.fromRaw(1));
    \\}
    },
    .{ .name = "byte_unit", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\export fn bad() void {
    \\    _ = a.units.Bytes(u64).fromRaw(1).add(a.units.Bits(u64).fromRaw(1));
    \\}
    },
    .{ .name = "clock_domain", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\const A = a.units.Instant(.awake, .second, i64);
    \\const B = a.units.Instant(.real, .second, i64);
    \\export fn bad() void {
    \\    _ = A.fromRaw(1).durationTo(B.fromRaw(1));
    \\}
    },
    .{ .name = "duration_unit", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\export fn bad() void {
    \\    _ = a.units.Duration(.second, u64).fromRaw(1).add(a.units.Duration(.millisecond, u64).fromRaw(1));
    \\}
    },
    .{ .name = "instant_add", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\const A = a.units.Instant(.awake, .second, i64);
    \\export fn bad() void {
    \\    _ = A.fromRaw(1).add(A.fromRaw(2));
    \\}
    },
    .{ .name = "integer_policy", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\fn take(_: a.int.Checked(u64)) void {}
    \\export fn bad() void {
    \\    take(a.int.Saturating(u64).init(1));
    \\}
    },
    .{ .name = "range_bounds", .message = "min <= max", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.int.Ranged(u8, 3, 1));
    \\}
    },
    .{ .name = "float_cast", .message = "integer source", .source =
    \\const a = @import("aegis");
    \\export fn bad() void {
    \\    _ = a.int.cast(u64, @as(f32, 1));
    \\}
    },
    .{ .name = "zero_width", .message = "nonzero-width", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.int.Checked(u0));
    \\}
    },
    .{ .name = "signed_counter", .message = "unsigned representation", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.id.Counter(struct {}, i64));
    \\}
    },
    .{ .name = "partial_encoding", .message = "whole-byte", .source =
    \\const a = @import("aegis");
    \\export fn bad() void {
    \\    _ = a.int.Checked(u7).init(1).toBytes(.big);
    \\}
    },
    .{ .name = "id_repr", .message = "ABI scalar requires", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.id.Id(struct {}, u3));
    \\}
    },
    .{ .name = "unit_repr", .message = "ABI scalar requires", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.units.Count(struct {}, i96));
    \\}
    },
    .{ .name = "range_repr", .message = "ABI scalar requires", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.int.Ranged(u24, 0, 1));
    \\}
    },
    .{ .name = "clock_width", .message = "whole-byte integer representation", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.units.Duration(.second, i12));
    \\}
    },
    .{ .name = "id_step", .message = "expected type", .source =
    \\const a = @import("aegis");
    \\const Seq = a.id.Id(struct {}, u64);
    \\export fn bad(seq: Seq) u64 {
    \\    const moved = seq.advance(a.units.Bytes(u64).fromRaw(1)) catch return 0;
    \\    return moved.raw();
    \\}
    },
    .{ .name = "id_signed_step", .message = "unsigned representation", .source =
    \\const a = @import("aegis");
    \\export fn bad() i32 {
    \\    const next = a.id.Id(struct {}, i32).fromRaw(1).successor() catch return 0;
    \\    return next.raw();
    \\}
    },
    .{ .name = "id_step_type", .message = "Step must be a units.Count", .source =
    \\const a = @import("aegis");
    \\const Tag = struct {
    \\    pub const Step = u32;
    \\};
    \\export fn bad() usize {
    \\    return @sizeOf(a.id.Id(Tag, u64).Step);
    \\}
    },
    .{ .name = "atomic_type", .message = "enum with an integer backing", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.Atomic(u32));
    \\}
    },
    .{ .name = "atomic_arith", .message = "add and sub take its own type", .source =
    \\const a = @import("aegis");
    \\export fn bad() u32 {
    \\    var cell: a.Atomic(a.id.Id(struct {}, u32)) = .init(.fromRaw(1));
    \\    return (cell.fetchAdd(.fromRaw(1), .monotonic) catch return 0).raw();
    \\}
    },
    .{ .name = "atomic_width", .message = "8, 16, 32 or 64-bit backing", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.Atomic(a.units.Duration(.nanosecond, i96)));
    \\}
    },
    .{ .name = "atomic_pointer_order", .message = "an address has no order here", .source =
    \\const a = @import("aegis");
    \\var target: u32 = 0;
    \\export fn bad() void {
    \\    var cell: a.Atomic(*u32) = .init(&target);
    \\    _ = cell.fetchMax(&target, .monotonic);
    \\}
    },
    .{ .name = "atomic_pointer_arith", .message = "add and sub take its own type", .source =
    \\const a = @import("aegis");
    \\var target: u32 = 0;
    \\export fn bad() void {
    \\    var cell: a.Atomic(*u32) = .init(&target);
    \\    _ = cell.fetchAddWrapping(&target, .monotonic);
    \\}
    },
    .{ .name = "atomic_slice", .message = "single-item pointer", .source =
    \\const a = @import("aegis");
    \\export fn bad() usize {
    \\    return @sizeOf(a.Atomic([]u8));
    \\}
    },
};

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.ZigExecutableRequired;
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(init.io, ".zig-cache/negative/cases");
    for (cases) |case| {
        const path = try a.print(".zig-cache/negative/cases/{s}.zig", .{case.name});
        try dir.writeFile(init.io, .{ .sub_path = path, .data = try a.print("{s}\n", .{case.source}) });
        const result = try std.process.run(init.gpa, init.io, .{ .argv = &.{ args[1], "build-obj", "--dep", "aegis", try a.print("-Mroot={s}", .{path}), "-Maegis=src/root.zig", "-fno-emit-bin", "--cache-dir", ".zig-cache/negative", "--global-cache-dir", ".zig-cache/global" }, .stdout_limit = .limited(4096), .stderr_limit = .limited(16384) });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited == 0 or std.mem.find(u8, result.stderr, case.message) == null) {
            var out = std.Io.File.stderr().writer(init.io, &.{});
            try out.interface.print("negative {s}: expected {s}\n{s}", .{ case.name, case.message, result.stderr });
            try out.interface.flush();
            return error.NegativeCaseNotDiagnosed;
        }
    }
}
