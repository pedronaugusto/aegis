//! The mode matrix: every deliberate contract violation, run in an isolated child process
//! (never a live station turn), with the module it belongs to and the builds it stops in.
//! The build compiles this program in each mode; ci/modes_check.zig runs every case in each
//! binary and requires a stop, with its message, exactly in the builds `when` names.
const std = @import("std");
const a = @import("aegis");

/// Debug only, Debug and ReleaseSafe (Zig's runtime safety), or every build.
pub const When = enum { debug, checked, always };

pub const Case = struct {
    /// The catalogue module whose release contract the case holds (ci/catalogue.zig).
    module: []const u8,
    name: []const u8,
    when: When,
    /// What the stop prints.
    message: []const u8,
    /// Whether it also runs where its check is compiled out, to show the check is gone there.
    /// False where the violation is itself undefined without the check (a deadlock, a use after
    /// free): such a run proves nothing.
    runs_unchecked: bool = true,
    run: *const fn (std.process.Init) anyerror!void,
};

pub const cases = [_]Case{
    .{ .module = "assert", .name = "invariant", .when = .always, .message = "required contract", .run = invariant },
    .{ .module = "assert", .name = "never", .when = .always, .message = "required contract", .run = never },
    .{ .module = "assert", .name = "assert-debug", .when = .debug, .message = "diagnostic contract", .run = debugOnly },
    .{ .module = "Secret", .name = "secret-move-overlap", .when = .always, .message = "@memcpy arguments alias", .run = secretMoveOverlap },
    .{ .module = "SecretBytes", .name = "bytes-move-overlap", .when = .always, .message = "@memcpy arguments alias", .run = bytesMoveOverlap },
    .{ .module = "Guarded", .name = "guarded-teardown-held", .when = .checked, .message = "reached unreachable code", .run = guardedTeardownHeld },
    .{ .module = "SpinRwGuarded", .name = "spin-rw-teardown-held", .when = .checked, .message = "reached unreachable code", .run = spinRwTeardownHeld },
    .{ .module = "BlockingGuarded", .name = "blocking-teardown-held", .when = .checked, .message = "reached unreachable code", .run = blockingTeardownHeld },
    .{ .module = "RwGuarded", .name = "rw-teardown-held", .when = .checked, .message = "reached unreachable code", .run = rwTeardownHeld },
    .{ .module = "Condition", .name = "association", .when = .always, .message = "condition used with a different owner", .run = association },
    .{ .module = "Once", .name = "once-recursive", .when = .debug, .message = "recursive Once initializer", .runs_unchecked = false, .run = onceRecursive },
    .{ .module = "Shared", .name = "shared-overflow", .when = .always, .message = "shared owner handle count overflow", .run = sharedOverflow },
    .{ .module = "Shared", .name = "shared-twice", .when = .debug, .message = "reached unreachable code", .runs_unchecked = false, .run = sharedTwice },
    .{ .module = "Order", .name = "order-same-owner", .when = .debug, .message = "SameOwner", .runs_unchecked = false, .run = orderSameOwner },
    .{ .module = "Confined", .name = "confined-access", .when = .checked, .message = "Confined accessed", .run = confinedAccess },
    .{ .module = "Confined", .name = "confined-handoff", .when = .checked, .message = "Confined accessed", .run = confinedHandoff },
    .{ .module = "bounded", .name = "budget-underflow", .when = .always, .message = "budget reservation underflow", .run = budgetUnderflow },
    .{ .module = "own", .name = "owned-twice", .when = .debug, .message = "reached unreachable code", .run = ownedTwice },
    .{ .module = "own", .name = "must-use", .when = .debug, .message = "required outcome inspection", .run = mustUse },
    .{ .module = "state", .name = "stage-reuse", .when = .debug, .message = "state stage used after its payload moved on", .run = stageReuse },
    .{ .module = "state", .name = "take-twice", .when = .debug, .message = "state stage used after its payload moved on", .run = takeTwice },
    .{ .module = "state", .name = "stage-alias", .when = .checked, .message = "state transition destination is its own source", .run = stageAlias },
    .{ .module = "state", .name = "commit-forged", .when = .always, .message = "state commit of an edge the machine does not declare", .run = commitForged },
    .{ .module = "scope", .name = "ref-expired", .when = .checked, .message = "scope reference used after its scope ended", .run = refExpired },
    .{ .module = "scope", .name = "ref-after-reuse", .when = .checked, .message = "scope reference used after its scope ended", .run = refAfterReuse },
    .{ .module = "scope", .name = "end-twice", .when = .checked, .message = "scope ended twice", .run = endTwice },
    .{ .module = "scope", .name = "ref-after-end", .when = .checked, .message = "scope used after it ended", .run = refAfterEnd },
    .{ .module = "scope", .name = "reborrow-expired", .when = .checked, .message = "scope reference used after its scope ended", .run = reborrowExpired },
    .{ .module = "scope", .name = "table-open", .when = .checked, .message = "scope table torn down with a scope still open", .run = tableOpen },
    .{ .module = "Region", .name = "region-second-grower", .when = .checked, .message = "region pushed while a tail is open", .run = regionSecondGrower },
    .{ .module = "Region", .name = "region-release-twice", .when = .checked, .message = "region mark released twice", .run = regionReleaseTwice },
    .{ .module = "Region", .name = "region-release-outer", .when = .checked, .message = "region mark released twice", .run = regionReleaseOuter },
    .{ .module = "Region", .name = "region-release-tail", .when = .checked, .message = "region released with a tail open", .run = regionReleaseTail },
    .{ .module = "Region", .name = "region-tail-sealed", .when = .checked, .message = "region tail used after it was sealed", .run = regionTailSealed },
    .{ .module = "handle", .name = "slot-free-twice", .when = .checked, .message = "slot freed twice", .run = slotFreeTwice },
    .{ .module = "handle", .name = "slot-out-of-range", .when = .always, .message = "slot handle out of range", .run = slotOutOfRange },
    .{ .module = "handle", .name = "run-free-twice", .when = .always, .message = "run freed twice", .run = runFreeTwice },
    .{ .module = "Region", .name = "region-tail-shrink", .when = .always, .message = "region tail shrunk past its length", .run = regionTailShrink },
    .{ .module = "flat", .name = "flat-wrong-variant", .when = .always, .message = "Flat union read as a variant it does not hold", .run = flatWrongVariant },
    .{ .module = "flat", .name = "flat-element-past", .when = .always, .message = "Flat element past its slice", .run = flatElementPast },
    .{ .module = "flat", .name = "flat-field-unset", .when = .always, .message = "Flat builder ended with a field unset", .run = flatFieldUnset },
    .{ .module = "flat", .name = "flat-set-twice", .when = .always, .message = "Flat field set twice", .run = flatSetTwice },
    .{ .module = "flat", .name = "flat-put-past", .when = .always, .message = "Flat element put past what was appended", .run = flatPutPast },
    .{ .module = "flat", .name = "flat-inner-open", .when = .always, .message = "Flat builder used while a part inside it is open", .run = flatInnerOpen },
};

/// One line, the message, and a failing exit on every host: no stack trace to symbolize, so
/// the check reads the same output in every mode and on every operating system.
pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    std.process.fatal("{s}", .{message});
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.CaseRequired;
    for (cases) |case| {
        if (std.mem.eql(u8, case.name, args[1])) return case.run(init);
    }
    return error.UnknownCase;
}

fn invariant(_: std.process.Init) !void {
    a.assert.invariant(false, "required contract");
}

fn never(_: std.process.Init) !void {
    a.assert.never("required contract");
}

fn debugOnly(_: std.process.Init) !void {
    a.assert.debug(false, "diagnostic contract");
}

fn secretMoveOverlap(_: std.process.Init) !void {
    var key = a.Secret([32]u8).init(@splat(7));
    key.moveInto(&key);
}

fn bytesMoveOverlap(_: std.process.Init) !void {
    var owner = try a.SecretBytes.init(std.heap.page_allocator, 0);
    owner.moveInto(&owner);
}

fn guardedTeardownHeld(_: std.process.Init) !void {
    var owner = a.Guarded(u64).init(1);
    var held = owner.acquire();
    defer held.deinit();
    std.mem.doNotOptimizeAway(owner.teardown());
}

fn spinRwTeardownHeld(_: std.process.Init) !void {
    var owner = a.SpinRwGuarded(u64).init(1);
    var held = owner.read();
    defer held.deinit();
    std.mem.doNotOptimizeAway(owner.teardown());
}

fn blockingTeardownHeld(init: std.process.Init) !void {
    var owner = a.BlockingGuarded(u64).init(1);
    var held = try owner.acquire(init.io);
    defer held.deinit(init.io);
    std.mem.doNotOptimizeAway(owner.teardown());
}

fn rwTeardownHeld(init: std.process.Init) !void {
    var owner = a.RwGuarded(u64).init(1);
    var held = try owner.read(init.io);
    defer held.deinit(init.io);
    std.mem.doNotOptimizeAway(owner.teardown());
}

fn association(init: std.process.Init) !void {
    var first = a.BlockingGuarded(u64).init(1);
    var second = a.BlockingGuarded(u64).init(2);
    var condition = a.Condition.initLimit(0);
    {
        var held = try first.acquire(init.io);
        defer held.deinit(init.io);
        held.wait(&condition, init.io, .none) catch |err| {
            if (err != error.WaiterLimit) return err;
        };
    }
    var other = try second.acquire(init.io);
    defer other.deinit(init.io);
    other.wait(&condition, init.io, .none) catch |err| {
        if (err != error.WaiterLimit) return err;
    };
}

const Recursive = struct {
    once: *a.Once(u64),
    task: *a.InitContext,
    fn initialize(io: std.Io, ctx: *Recursive, _: *u64) (std.Io.Cancelable || error{WaiterLimit})!void {
        _ = try ctx.once.getOrInit(io, ctx.task, ctx, initialize);
    }
};

fn onceRecursive(init: std.process.Init) !void {
    var once = a.Once(u64).init();
    var task: a.InitContext = .{};
    var ctx: Recursive = .{ .once = &once, .task = &task };
    _ = try once.getOrInit(init.io, &task, &ctx, Recursive.initialize);
}

fn cleanup(value: *u64) void {
    value.* = 0;
}

const S = a.Shared(u64, cleanup);

fn sharedOverflow(_: std.process.Init) !void {
    var owner = try S.create(std.heap.page_allocator, 1);
    owner.block.count.store(S.maximum_handles, .monotonic);
    _ = owner.retain();
}

fn sharedTwice(_: std.process.Init) !void {
    var owner = try S.create(std.heap.page_allocator, 1);
    var other = owner.retain();
    owner.release();
    owner.release();
    other.release();
}

const O = a.Order(&.{.{ .name = "one" }});

fn orderSameOwner(init: std.process.Init) !void {
    var context: O.Context = .{};
    var owner = O.Ordered(a.BlockingGuarded(u64), 0).init(.init(0));
    var held = try owner.acquireOrdered(init.io, &context);
    defer held.deinit(init.io);
    var recursive = try owner.acquireOrdered(init.io, &context);
    recursive.deinit(init.io);
}

fn confinedAccess(_: std.process.Init) !void {
    var value = a.Confined(u64).init(@fromBackingInt(@intCast(1)), 7);
    std.mem.doNotOptimizeAway(value.value(@fromBackingInt(@intCast(2))).*);
}

fn confinedHandoff(_: std.process.Init) !void {
    var value = a.Confined(u64).init(@fromBackingInt(@intCast(1)), 7);
    value.handOff(@fromBackingInt(@intCast(2)), @fromBackingInt(@intCast(3)));
}

fn budgetUnderflow(_: std.process.Init) !void {
    var budget = a.bounded.Budget(u8).init(1);
    var reservation = try budget.reserve(1);
    budget.taken = 0;
    reservation.release();
}

fn ownedTwice(_: std.process.Init) !void {
    var owner = a.own.Owned(u64, cleanup).init(1);
    owner.deinit();
    owner.deinit();
}

fn mustUse(_: std.process.Init) !void {
    var outcome = a.own.MustUse(u64, "required outcome inspection").init(1);
    outcome.deinit();
}

const Link = a.state.Machine(enum { idle, open, closed }, enum { dial, drop, close }, .{
    .initial = .idle,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .idle, .on = .dial, .to = .open },
        .{ .from = .idle, .on = .drop, .to = .idle },
        .{ .from = .open, .on = .close, .to = .closed },
    },
});

fn stageReuse(_: std.process.Init) !void {
    var idle = Link.At(.idle, u64).init(1);
    var open: Link.At(.open, u64) = undefined;
    idle.transition(.dial, &open);
    std.mem.doNotOptimizeAway(idle.get().*);
}

fn takeTwice(_: std.process.Init) !void {
    var idle = Link.At(.idle, u64).init(1);
    var open: Link.At(.open, u64) = undefined;
    idle.transition(.dial, &open);
    var closed: Link.At(.closed, u64) = undefined;
    open.transition(.close, &closed);
    var out: u64 = undefined;
    closed.take(&out);
    closed.take(&out);
}

fn stageAlias(_: std.process.Init) !void {
    var idle = Link.At(.idle, u64).init(1);
    const same: *Link.At(.idle, u64) = &idle;
    same.transition(.drop, same);
}

fn commitForged(_: std.process.Init) !void {
    var link = Link.Runtime(u64).init(1);
    try link.commit(.{ .from = .idle, .on = .close, .to = .closed });
}

const Request = struct {};
const Connection = struct {};
var storage: u64 = 0xfeed;

fn refExpired(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    const request = try table.open();
    const view = request.ref(&storage);
    request.end();
    std.mem.doNotOptimizeAway(view.get().*);
}

fn refAfterReuse(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    const first = try table.open();
    const stale = first.ref(&storage);
    first.end();
    const second = try table.open();
    defer second.end();
    std.mem.doNotOptimizeAway(stale.get().*);
}

fn endTwice(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    const request = try table.open();
    request.end();
    request.end();
}

fn refAfterEnd(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    const request = try table.open();
    request.end();
    std.mem.doNotOptimizeAway(request.ref(&storage));
}

fn reborrowExpired(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    var other_slots: [1]a.scope.Table(Connection).Slot = undefined;
    var other = a.scope.Table(Connection).init(&other_slots);
    defer other.deinit();
    const request = try table.open();
    const connection = other.open() catch unreachable; // unreachable: a table of one slot opens its first scope
    const view = request.ref(&storage);
    request.end();
    std.mem.doNotOptimizeAway(connection.reborrow(view));
}

fn tableOpen(_: std.process.Init) !void {
    var open_slots: [1]a.scope.Table(Request).Slot = undefined;
    var open = a.scope.Table(Request).init(&open_slots);
    errdefer open.deinit();
    // The scope stays open: the teardown below is the violation.
    _ = try open.open();
    open.deinit();
}

fn region() !a.Region {
    return a.Region.reserve(.init(1 << 20));
}

fn regionSecondGrower(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    var items = try r.tail(u64);
    _ = try items.append(1);
    std.mem.doNotOptimizeAway(try r.create(u64));
}

fn regionReleaseTwice(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    const m = r.mark();
    _ = try r.push(u8, 16);
    r.release(m);
    r.release(m);
}

fn regionReleaseOuter(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    const outer = r.mark();
    _ = try r.push(u8, 16);
    const inner = r.mark();
    r.release(outer);
    _ = try r.push(u8, 64);
    r.release(inner);
}

fn regionReleaseTail(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    const m = r.mark();
    var items = try r.tail(u64);
    _ = try items.append(1);
    r.release(m);
}

fn regionTailSealed(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    var items = try r.tail(u64);
    _ = items.seal();
    std.mem.doNotOptimizeAway(try items.append(2));
}

fn regionTailShrink(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    var items = try r.tail(u64);
    _ = try items.append(1);
    items.shrink(2);
}

const Slots = a.handle.SlotPool(u64, struct {}, .{});

fn slotFreeTwice(_: std.process.Init) !void {
    var pool = Slots.init(try region());
    defer pool.deinit();
    const h = try pool.alloc(1);
    pool.free(h);
    pool.free(h);
}

fn slotOutOfRange(_: std.process.Init) !void {
    var pool = Slots.init(try region());
    defer pool.deinit();
    _ = try pool.alloc(1);
    std.mem.doNotOptimizeAway(pool.get(@fromBackingInt(1)).*);
}

fn runFreeTwice(_: std.process.Init) !void {
    var pool = a.handle.RunPool(u64, struct {}).init(try region(), try region());
    defer pool.deinit();
    const first = try pool.alloc(4);
    _ = try pool.alloc(4);
    pool.free(first);
    pool.free(first);
}

const FlatPick = union(enum) { n: u32, s: []const u8 };
const FlatPair = struct { a: u32, s: []const u8 };

fn flatWrongVariant(_: std.process.Init) !void {
    var buffer: [64]u8 align(a.flat.alignment) = undefined;
    const n = try a.flat.Flat(FlatPick).write(.{ .n = 1 }, &buffer);
    std.mem.doNotOptimizeAway(a.flat.Flat(FlatPick).view(buffer[0..n]).get(.s).len);
}

fn flatElementPast(_: std.process.Init) !void {
    var buffer: [64]u8 align(a.flat.alignment) = undefined;
    const n = try a.flat.Flat([]const u16).write(&.{ 1, 2 }, &buffer);
    std.mem.doNotOptimizeAway(a.flat.Flat([]const u16).view(buffer[0..n]).at(2));
}

/// A root builder on an image in its own region; `run` gets the root.
fn flatBuild(comptime run: fn (*a.flat.Flat(FlatPair).Builder) anyerror!void) !void {
    var r = try region();
    defer r.deinit();
    var tail = try r.tail(u8);
    var image = try a.flat.Image.init(&tail, .init(4));
    var root = try a.flat.Flat(FlatPair).builder(&image);
    try run(&root);
}

fn flatFieldUnset(_: std.process.Init) !void {
    try flatBuild(struct {
        fn run(root: *a.flat.Flat(FlatPair).Builder) !void {
            try root.set(.a, 1);
            root.end();
        }
    }.run);
}

fn flatSetTwice(_: std.process.Init) !void {
    try flatBuild(struct {
        fn run(root: *a.flat.Flat(FlatPair).Builder) !void {
            try root.set(.a, 1);
            try root.set(.a, 2);
        }
    }.run);
}

fn flatInnerOpen(_: std.process.Init) !void {
    try flatBuild(struct {
        fn run(root: *a.flat.Flat(FlatPair).Builder) !void {
            var s = try root.begin(.s);
            try s.append('x');
            try root.set(.a, 1);
        }
    }.run);
}

fn flatPutPast(_: std.process.Init) !void {
    var r = try region();
    defer r.deinit();
    var tail = try r.tail(u8);
    var image = try a.flat.Image.init(&tail, .init(4));
    var root = try a.flat.Flat(FlatPair).builder(&image);
    var s = try root.begin(.s);
    try s.append('x');
    s.put(1, 'y');
}
