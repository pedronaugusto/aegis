//! Each module's types beside the hand-written storage that does the same job, with the
//! builds in which the two must have the same size and alignment. The build compiles this
//! file as an object for every portable profile in every mode: a row that does not hold is a
//! compile error naming it. The object carries the rendered table, which the artifacts step
//! reads back out, so the layout of every profile is recorded without running on it.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");
const DirectCondition = @import("DirectCondition.zig");

/// The builds a row's sizes must agree in: every build, every build but Debug (a Debug-only
/// diagnostic field), or ReleaseFast and ReleaseSmall (a check that follows Zig's runtime
/// safety, so ReleaseSafe keeps its field too).
pub const Equal = enum { every, release, unchecked };

pub const Row = struct {
    /// The catalogue module (ci/catalogue.zig).
    module: []const u8,
    /// The type as written.
    label: []const u8,
    aegis: type,
    /// The hand-written storage with the same job.
    direct: type,
    equal: Equal,
};

const Tag = struct {};
const Material = struct { key: [32]u8, nonce: u64, flags: u16 };
const States = enum { idle, open, closed };
const Link = a.state.Machine(States, enum { dial, close }, .{
    .initial = .idle,
    .terminal = &.{.closed},
    .edges = &.{ .{ .from = .idle, .on = .dial, .to = .open }, .{ .from = .open, .on = .close, .to = .closed } },
});
const Frame = struct {
    pub const aegis_public_frame = true;
    phase: u8,
    offset: u32,
};
fn cleanup(_: *u64) void {}
fn cleanupIo(_: *u64, _: std.Io) void {}
const Pool = a.handle.Pool(u64, Tag);

pub const rows = [_]Row{
    .{ .module = "Secret", .label = "Secret([32]u8)", .aegis = a.Secret([32]u8), .direct = [32]u8, .equal = .every },
    .{ .module = "Secret", .label = "Secret(Material)", .aegis = a.Secret(Material), .direct = Material, .equal = .every },
    .{ .module = "SecretBytes", .label = "SecretBytes", .aegis = a.SecretBytes, .direct = struct { gpa: std.mem.Allocator, allocation: []u8, used_len: usize }, .equal = .every },
    .{ .module = "secret", .label = "secret.Choice", .aegis = a.secret.Choice, .direct = u1, .equal = .every },
    .{ .module = "secret", .label = "secret.OrderChoices", .aegis = a.secret.OrderChoices, .direct = struct { lt: u1, eq: u1, gt: u1 }, .equal = .every },
    .{ .module = "secret.Timing", .label = "secret.Timing", .aegis = a.secret.Timing, .direct = u64, .equal = .every },
    .{ .module = "Guarded", .label = "Guarded(u64)", .aegis = a.Guarded(u64), .direct = struct { lock: std.atomic.Value(bool), data: u64 }, .equal = .every },
    .{ .module = "Guarded", .label = "Guarded(u64).Guard", .aegis = a.Guarded(u64).Guard, .direct = *anyopaque, .equal = .every },
    .{ .module = "SpinRwGuarded", .label = "SpinRwGuarded(u64)", .aegis = a.SpinRwGuarded(u64), .direct = struct { state: std.atomic.Value(u32), data: u64 }, .equal = .every },
    .{ .module = "SpinRwGuarded", .label = "SpinRwGuarded(u64).ReadGuard", .aegis = a.SpinRwGuarded(u64).ReadGuard, .direct = *anyopaque, .equal = .every },
    .{ .module = "BlockingGuarded", .label = "BlockingGuarded(u64)", .aegis = a.BlockingGuarded(u64), .direct = struct { mutex: std.Io.Mutex, data: u64 }, .equal = .every },
    .{ .module = "BlockingGuarded", .label = "BlockingGuarded(u64).Guard", .aegis = a.BlockingGuarded(u64).Guard, .direct = *anyopaque, .equal = .every },
    .{ .module = "RwGuarded", .label = "RwGuarded(u64)", .aegis = a.RwGuarded(u64), .direct = struct { lock: std.Io.RwLock, admitted: std.atomic.Value(usize), limit: usize, data: u64 }, .equal = .every },
    .{ .module = "RwGuarded", .label = "RwGuarded(u64).ReadGuard", .aegis = a.RwGuarded(u64).ReadGuard, .direct = *anyopaque, .equal = .every },
    .{ .module = "Condition", .label = "Condition", .aegis = a.Condition, .direct = DirectCondition, .equal = .every },
    .{ .module = "Once", .label = "Once(u64)", .aegis = a.Once(u64), .direct = struct { state: std.atomic.Value(enum(u8) { empty, running, ready }), mutex: std.Io.Mutex, changed: DirectCondition, data: u64 }, .equal = .every },
    .{ .module = "Once", .label = "InitContext", .aegis = a.InitContext, .direct = void, .equal = .release },
    .{ .module = "Lazy", .label = "Lazy(u64)", .aegis = a.Lazy(u64), .direct = struct { state: std.atomic.Value(enum(u8) { empty, ready }), mutex: std.Io.Mutex, data: u64 }, .equal = .every },
    .{ .module = "Atomic", .label = "Atomic(units.Bytes(u64))", .aegis = a.Atomic(a.units.Bytes(u64)), .direct = std.atomic.Value(u64), .equal = .every },
    .{ .module = "Shared", .label = "Shared(u64, cleanup)", .aegis = a.Shared(u64, cleanup), .direct = *anyopaque, .equal = .release },
    .{ .module = "Confined", .label = "Confined(u64)", .aegis = a.Confined(u64), .direct = u64, .equal = .unchecked },
    .{ .module = "int", .label = "int.Checked(u32)", .aegis = a.int.Checked(u32), .direct = u32, .equal = .every },
    .{ .module = "int", .label = "int.Saturating(i64)", .aegis = a.int.Saturating(i64), .direct = i64, .equal = .every },
    .{ .module = "int", .label = "int.Ranged(u8, 1, 9)", .aegis = a.int.Ranged(u8, 1, 9), .direct = u8, .equal = .every },
    .{ .module = "id", .label = "id.Id(Tag, u64)", .aegis = a.id.Id(Tag, u64), .direct = u64, .equal = .every },
    .{ .module = "id", .label = "id.NonZero(Tag, u32)", .aegis = a.id.NonZero(Tag, u32), .direct = u32, .equal = .every },
    .{ .module = "id", .label = "id.Counter(Tag, u64)", .aegis = a.id.Counter(Tag, u64), .direct = u64, .equal = .every },
    .{ .module = "units", .label = "units.Count(Tag, u32)", .aegis = a.units.Count(Tag, u32), .direct = u32, .equal = .every },
    .{ .module = "units", .label = "units.Bytes(usize)", .aegis = a.units.Bytes(usize), .direct = usize, .equal = .every },
    .{ .module = "units", .label = "units.Duration(.millisecond, i64)", .aegis = a.units.Duration(.millisecond, i64), .direct = i64, .equal = .every },
    .{ .module = "units", .label = "units.Instant(.awake, .nanosecond, i96)", .aegis = a.units.Instant(.awake, .nanosecond, i96), .direct = i96, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Array(u64, 4)", .aegis = a.bounded.Array(u64, 4), .direct = struct { storage: [4]u64, used: usize }, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Queue(u64, 4)", .aegis = a.bounded.Queue(u64, 4), .direct = struct { storage: [4]u64, head: usize, used: usize }, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Buffer(u64)", .aegis = a.bounded.Buffer(u64), .direct = struct { storage: []u64, gpa: ?std.mem.Allocator, maximum: usize, used: usize }, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Limit(u32)", .aegis = a.bounded.Limit(u32), .direct = u32, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Budget(u32)", .aegis = a.bounded.Budget(u32), .direct = struct { ceiling: u32, taken: u32 }, .equal = .every },
    .{ .module = "bounded", .label = "bounded.Budget(u32).Reservation", .aegis = a.bounded.Budget(u32).Reservation, .direct = struct { budget: *anyopaque, amount: u32 }, .equal = .release },
    .{ .module = "own", .label = "own.Owned(u64, cleanup)", .aegis = a.own.Owned(u64, cleanup), .direct = u64, .equal = .release },
    .{ .module = "own", .label = "own.OwnedIo(u64, cleanup)", .aegis = a.own.OwnedIo(u64, cleanupIo), .direct = u64, .equal = .release },
    .{ .module = "own", .label = "own.MustUse(u64, obligation)", .aegis = a.own.MustUse(u64, "read"), .direct = u64, .equal = .release },
    .{ .module = "state", .label = "state.Machine(...).At(.idle, u64)", .aegis = Link.At(.idle, u64), .direct = u64, .equal = .release },
    .{ .module = "state", .label = "state.Machine(...).Runtime(u64)", .aegis = Link.Runtime(u64), .direct = struct { payload: u64, state: States }, .equal = .every },
    .{ .module = "scope", .label = "scope.Ref(Brand, *u64)", .aegis = a.scope.Ref(Tag, *u64), .direct = *u64, .equal = .unchecked },
    .{ .module = "scope", .label = "scope.Ref(Brand, []u8)", .aegis = a.scope.Ref(Tag, []u8), .direct = []u8, .equal = .unchecked },
    .{ .module = "scope", .label = "scope.Table(Brand)", .aegis = a.scope.Table(Tag), .direct = void, .equal = .unchecked },
    .{ .module = "handle", .label = "handle.Pool(u64, Tag).Key", .aegis = Pool.Key, .direct = struct { instance: struct { namespace: u128, serial: u64 }, index: usize, generation: u64 }, .equal = .every },
    .{ .module = "handle", .label = "handle.Index(Tag, u32)", .aegis = a.handle.Index(Tag, u32), .direct = u32, .equal = .every },
    .{ .module = "input", .label = "input.Untrusted([]const u8)", .aegis = a.input.Untrusted([]const u8), .direct = []const u8, .equal = .every },
    .{ .module = "input", .label = "input.Untrusted(u32)", .aegis = a.input.Untrusted(u32), .direct = u32, .equal = .every },
    .{ .module = "err", .label = "err.Context(Frame, 4)", .aegis = a.err.Context(Frame, 4), .direct = struct { buffer: [4]Frame, len: usize, truncated: bool }, .equal = .every },
    .{ .module = "err", .label = "err.PublicText(16)", .aegis = a.err.PublicText(16), .direct = struct { bytes: [16]u8, len: usize, truncated: bool }, .equal = .every },
};

/// A row's module and label, for code that runs: the rows themselves hold types.
pub const Name = struct { module: []const u8, label: []const u8 };
pub const names: [rows.len]Name = blk: {
    var out: [rows.len]Name = undefined;
    for (&out, rows) |*name, row| name.* = .{ .module = row.module, .label = row.label };
    break :blk out;
};

fn required(equal: Equal) bool {
    return switch (equal) {
        .every => true,
        .release => builtin.optimize != .debug,
        .unchecked => builtin.optimize == .fast or builtin.optimize == .small,
    };
}

comptime {
    @setEvalBranchQuota(100_000);
    for (rows) |row| {
        if (required(row.equal) and (@sizeOf(row.aegis) != @sizeOf(row.direct) or @alignOf(row.aegis) != @alignOf(row.direct)))
            @compileError(std.fmt.comptimePrint("{s} {s}: {d} bytes aligned {d}, hand-written {d} aligned {d}", .{ row.module, row.label, @sizeOf(row.aegis), @alignOf(row.aegis), @sizeOf(row.direct), @alignOf(row.direct) }));
    }
}

/// What the artifacts step looks for in the object: the table starts after it.
pub const begin_marker = "aegis layout report\n";
pub const end_marker = "\nend of aegis layout report\n";

const report = blk: {
    @setEvalBranchQuota(1_000_000);
    var text: []const u8 = begin_marker ++ std.fmt.comptimePrint("# Layouts: {s}-{s}-{s}, {t}\n\n", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), @tagName(builtin.abi), builtin.optimize });
    text = text ++ "Bytes and alignment of each type and of the hand-written storage with its job. `equal` names the builds in which they must match; this build holds every row it names.\n\n| Module | Type | aegis | Hand-written | Equal in |\n|---|---|---|---|---|\n";
    for (rows) |row| text = text ++ std.fmt.comptimePrint("| {s} | `{s}` | {d}/{d} | {d}/{d} | {s} |\n", .{ row.module, row.label, @sizeOf(row.aegis), @alignOf(row.aegis), @sizeOf(row.direct), @alignOf(row.direct), switch (row.equal) {
        .every => "every build",
        .release => "ReleaseSafe, ReleaseFast, ReleaseSmall",
        .unchecked => "ReleaseFast, ReleaseSmall",
    } });
    break :blk text ++ end_marker;
};

export const aegis_layout_report: [report.len]u8 = report[0..report.len].*;
