//! Every generic type aegis declares, made at a representative parameter, with each of its
//! declarations referenced: a method nothing inside aegis calls compiles here, so one left
//! broken (a field renamed and a read of it missed, 688eb2b's aegis_ rename) fails aegis's own
//! tests, not a caller's build. `refAllDecls` reaches neither an inline method nor one a lock
//! type answers by its shape (Order's acquisitions over each lock): those are named. A comptime
//! walk of aegis's public surface fails the build for a type function `made` lacks, so a new one
//! joins the table as it is written.
const std = @import("std");
const aegis = @import("../root.zig");
const r = std.testing.refAllDecls;
const Tag = struct {};
const States = enum { idle, open };
const Events = enum { start };
fn noop(_: *u32) void {}
fn noopIo(_: *u32, _: std.Io) void {}

const Machine = aegis.state.Machine(States, Events, .{ .initial = .idle, .terminal = &.{.open}, .edges = &.{.{ .from = .idle, .on = .start, .to = .open }} });
const Ordering = aegis.Order(&.{ .{ .name = "a" }, .{ .name = "b", .after = &.{0} } });
const Dense = aegis.handle.DenseSlotMap(u32, Tag);
const Laid = struct { id: u32, name: []const u8 };
const Carved = struct { bytes: []u8, words: []u32 };

/// Each public type function by its path from aegis's root, made at a representative parameter.
const made = .{
    .{ "Secret", aegis.Secret(u32) },
    .{ "Guarded", aegis.Guarded(u32) },
    .{ "BlockingGuarded", aegis.BlockingGuarded(u32) },
    .{ "RwGuarded", aegis.RwGuarded(u32) },
    .{ "SpinRwGuarded", aegis.SpinRwGuarded(u32) },
    .{ "Once", aegis.Once(u32) },
    .{ "Lazy", aegis.Lazy(u32) },
    .{ "Signal", aegis.Signal(u32) },
    .{ "Atomic", aegis.Atomic(aegis.units.Count(Tag, u16)) },
    .{ "Shared", aegis.Shared(u32, noop) },
    .{ "Order", Ordering },
    .{ "Confined", aegis.Confined(u32) },
    .{ "int.Lifted", aegis.int.Lifted(u64, u32, u32) },
    .{ "int.Checked", aegis.int.Checked(u32) },
    .{ "int.Saturating", aegis.int.Saturating(u32) },
    .{ "int.Ranged", aegis.int.Ranged(u8, 1, 9) },
    .{ "id.Id", aegis.id.Id(Tag, u32) },
    .{ "id.NonZero", aegis.id.NonZero(Tag, u32) },
    .{ "id.Counter", aegis.id.Counter(Tag, u32) },
    .{ "units.Count", aegis.units.Count(Tag, u32) },
    .{ "units.Bytes", aegis.units.Bytes(u64) },
    .{ "units.Bits", aegis.units.Bits(u64) },
    .{ "units.Duration", aegis.units.Duration(.millisecond, i64) },
    .{ "units.Instant", aegis.units.Instant(.awake, .nanosecond, i96) },
    .{ "own.Owned", aegis.own.Owned(u32, noop) },
    .{ "own.OwnedIo", aegis.own.OwnedIo(u32, noopIo) },
    .{ "own.Unowned", aegis.own.Unowned(std.Io.File) },
    .{ "own.MustUse", aegis.own.MustUse(u32, "x") },
    .{ "state.Edge", aegis.state.Edge(States, Events) },
    .{ "state.Spec", aegis.state.Spec(States, Events) },
    .{ "state.Machine", Machine },
    .{ "scope.Table", aegis.scope.Table(Tag) },
    .{ "scope.Ref", aegis.scope.Ref(Tag, *u32) },
    .{ "flat.Flat", aegis.flat.Flat(Laid) },
    .{ "parts.Block", aegis.parts.Block(Carved) },
    .{ "parts.Counts", aegis.parts.Counts(Carved) },
    .{ "parts.Given", aegis.parts.Given([]const u8) },
    .{ "parts.Repeat", aegis.parts.Repeat(struct { xs: []u16 }) },
    .{ "handle.Index", aegis.handle.Index(Tag, u32) },
    .{ "handle.OptionalIndex", aegis.handle.OptionalIndex(Tag, u32) },
    .{ "handle.Offset", aegis.handle.Offset(Tag, u32) },
    .{ "handle.SlotPool", aegis.handle.SlotPool(u32, Tag, .{}) },
    .{ "handle.RunPool", aegis.handle.RunPool(u32, Tag) },
    .{ "handle.DenseSlotMap", Dense },
    .{ "handle.SecondaryMap", aegis.handle.SecondaryMap(Dense, u32) },
    .{ "input.Untrusted", aegis.input.Untrusted(u32) },
    .{ "err.PublicText", aegis.err.PublicText(12) },
    .{ "err.Context", aegis.err.Context(u8, 2) },
    .{ "err.Failure", aegis.err.Failure(error{Refused}, u8, 2) },
    .{ "bounded.Array", aegis.bounded.Array(u8, 4) },
    .{ "bounded.Ring", aegis.bounded.Ring(u8, 4) },
    .{ "bounded.Buffer", aegis.bounded.Buffer(u8) },
    .{ "bounded.RingBuffer", aegis.bounded.RingBuffer(u8) },
    .{ "bounded.Limit", aegis.bounded.Limit(u32) },
    .{ "bounded.Budget", aegis.bounded.Budget(u32) },
};

/// A made type's declarations referenced, where it has any: `int.Lifted` makes an integer or an
/// error union of one.
fn make(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => r(T),
        else => {},
    }
}

test "every public type function, made at a representative parameter, compiles every method it declares" {
    inline for (made) |entry| make(entry[1]);
    // The forms the walk below does not name: a pool's keyed form beside its indexed one, a
    // machine's own type functions, each lock Order ranks, and the types a value carries.
    r(aegis.handle.SlotPool(u32, Tag, .{ .generation = u32 }));
    // A stage's methods are its state's: the initial one is made, a terminal one taken from.
    inline for (.{ "init", "initFrom", "get", "getConst" }) |m| _ = &@field(Machine.At(.idle, u32), m);
    inline for (.{ "get", "getConst", "take" }) |m| _ = &@field(Machine.At(.open, u32), m);
    r(Machine.Runtime(u32));
    r(Machine.Carrying(union(States) { idle: u32, open: void }));
    const Rw = Ordering.Ordered(aegis.RwGuarded(u32), 0);
    const Bl = Ordering.Ordered(aegis.BlockingGuarded(u32), 1);
    inline for (.{ "init", "readOrdered", "writeOrdered", "readOrderedUncancelable", "writeOrderedUncancelable" }) |m| _ = &@field(Rw, m);
    inline for (.{ "init", "acquireOrdered", "acquireOrderedUncancelable" }) |m| _ = &@field(Bl, m);
    const Cap = @typeInfo(@typeInfo(@TypeOf(Bl.acquireOrdered)).@"fn".return_type.?).error_union.payload;
    r(Cap);
    const RCap = @typeInfo(@typeInfo(@TypeOf(Rw.readOrdered)).@"fn".return_type.?).error_union.payload;
    inline for (.{ "value", "deinit" }) |m| _ = &@field(RCap, m);
    r(aegis.Guarded(u32).Handoff);
    r(aegis.Region.Tail(u32));
    r(aegis.Pulse);
}

/// The public type functions under `T` (aegis's root, then each namespace it exports), by path.
fn typeFunctions(comptime T: type, comptime prefix: []const u8, comptime depth: usize) []const []const u8 {
    comptime {
        var found: []const []const u8 = &.{};
        if (depth == 4) return found;
        for (std.meta.declarations(T)) |name| {
            if (std.mem.eql(u8, name, "lint_rules")) continue;
            const value = @field(T, name);
            const path = prefix ++ name;
            switch (@typeInfo(@TypeOf(value))) {
                .@"fn" => |function| if (function.return_type == type) {
                    found = found ++ .{path};
                },
                .type => if (@typeInfo(value) == .@"struct" and @typeInfo(value).@"struct".field_names.len == 0) {
                    found = found ++ typeFunctions(value, path ++ ".", depth + 1);
                },
                else => {},
            }
        }
        return found;
    }
}

test "every public type function aegis declares is made above, so a new one joins the table" {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var missing: []const u8 = "";
        for (typeFunctions(aegis, "", 0)) |path| {
            const listed = listed: {
                for (@typeInfo(@TypeOf(made)).@"struct".field_names) |field| {
                    if (std.mem.eql(u8, @field(made, field)[0], path)) break :listed true;
                }
                break :listed false;
            };
            if (!listed) missing = missing ++ " " ++ path;
        }
        if (missing.len != 0) @compileError("type functions instances_test.zig does not make:" ++ missing);
    }
}
