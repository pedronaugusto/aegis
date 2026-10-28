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
    // aegis: design: never released, as the retain past the limit stops the run in every build; an isolated child process runs it
    var owner = try S.create(std.heap.page_allocator, 1);
    // aegis: design: a deliberately corrupted count in an isolated child process; it isolates the all-mode limit
    owner.block.count.store(S.maximum_handles, .monotonic);
    _ = owner.retain();
}

fn sharedTwice(_: std.process.Init) !void {
    var owner = try S.create(std.heap.page_allocator, 1);
    var other = owner.retain();
    owner.release();
    // aegis: design: the deliberate second release the checked builds stop on; an isolated child process runs it
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
    // aegis: design: a deliberately corrupted admission state in an isolated child process; it isolates the all-mode underflow check
    budget.taken = 0;
    reservation.release();
}

fn ownedTwice(_: std.process.Init) !void {
    var owner = a.own.Owned(u64, cleanup).init(1);
    owner.deinit();
    // aegis: design: the deliberate second release the checked builds stop on; an isolated child process runs it
    owner.deinit();
}

fn mustUse(_: std.process.Init) !void {
    // aegis: design: the deliberately undischarged result the checked builds stop on; an isolated child process runs it
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
    // aegis: design: the deliberate second end the checked builds stop on; an isolated child process runs it
    request.end();
}

fn refAfterEnd(_: std.process.Init) !void {
    var slots: [1]a.scope.Table(Request).Slot = undefined;
    var table = a.scope.Table(Request).init(&slots);
    defer table.deinit();
    const request = try table.open();
    request.end();
    // aegis: design: the deliberate use of an ended scope the checked builds stop on; an isolated child process runs it
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
    // aegis: design: left open, as the checked builds stop at the stale reborrow before its end; an isolated child process runs it
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
