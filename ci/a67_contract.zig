//! Deliberate contract violations in isolated child processes, never live station turns.
const std = @import("std");
const a = @import("aegis");
const O = a.Order(&.{.{ .name = "one" }});
fn cleanup(value: *u64) void {
    value.* = 0;
}
const S = a.Shared(u64, cleanup);
const Recursive = struct {
    once: *a.Once(u64),
    task: *a.InitContext,
    fn initialize(io: std.Io, ctx: *Recursive, _: *u64) (std.Io.Cancelable || error{WaiterLimit})!void {
        _ = try ctx.once.getOrInit(io, ctx.task, ctx, initialize);
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const name = args[1];
    if (std.mem.eql(u8, name, "confined-access")) {
        var value = a.Confined(u64).init(@fromBackingInt(@intCast(1)), 7);
        std.mem.doNotOptimizeAway(value.value(@fromBackingInt(@intCast(2))).*);
    } else if (std.mem.eql(u8, name, "confined-handoff")) {
        var value = a.Confined(u64).init(@fromBackingInt(@intCast(1)), 7);
        value.handOff(@fromBackingInt(@intCast(2)), @fromBackingInt(@intCast(3)));
    } else if (std.mem.eql(u8, name, "order")) {
        var context: O.Context = .{};
        var owner = O.Ordered(a.BlockingGuarded(u64), 0).init(.init(0));
        var held = try owner.acquireOrdered(init.io, &context);
        defer held.deinit(init.io);
        var recursive = try owner.acquireOrdered(init.io, &context);
        recursive.deinit(init.io);
    } else if (std.mem.eql(u8, name, "once")) {
        var once = a.Once(u64).init();
        var task: a.InitContext = .{};
        var ctx: Recursive = .{ .once = &once, .task = &task };
        _ = try once.getOrInit(init.io, &task, &ctx, Recursive.initialize);
    } else if (std.mem.eql(u8, name, "owned")) {
        var owner = a.own.Owned(u64, cleanup).init(1);
        owner.deinit();
        // glint-ignore: A003 -- design: the deliberate second release the checked builds stop on; an isolated child process runs it
        owner.deinit();
    } else if (std.mem.eql(u8, name, "must-use")) {
        // glint-ignore: A003 -- design: the deliberately undischarged result the checked builds stop on; an isolated child process runs it
        var outcome = a.own.MustUse(u64, "required outcome inspection").init(1);
        outcome.deinit();
    } else if (std.mem.eql(u8, name, "association")) {
        var first = a.BlockingGuarded(u64).init(1);
        var second = a.BlockingGuarded(u64).init(2);
        var condition = a.Condition.initLimit(0);
        {
            var held = try first.acquire(init.io);
            defer held.deinit(init.io);
            condition.wait(init.io, &held, .none) catch |err| {
                if (err != error.WaiterLimit) return err;
            };
        }
        var other = try second.acquire(init.io);
        defer other.deinit(init.io);
        condition.wait(init.io, &other, .none) catch |err| {
            if (err != error.WaiterLimit) return err;
        };
    } else if (std.mem.eql(u8, name, "budget")) {
        var budget = a.bounded.Budget(u8).init(1);
        var reservation = try budget.reserve(1);
        // glint-ignore: A001 -- design: a deliberately corrupted admission state in an isolated child process; it isolates the all-mode underflow check
        budget.taken = 0;
        reservation.release();
    } else if (std.mem.eql(u8, name, "shared-overflow")) {
        // glint-ignore: A003 -- design: never released, as the retain past the limit stops the run in every build; an isolated child process runs it
        var owner = try S.create(std.heap.page_allocator, 1);
        // glint-ignore: A001 -- design: a deliberately corrupted count in an isolated child process; it isolates the all-mode limit
        owner.block.count.store(S.maximum_handles, .monotonic);
        _ = owner.retain();
    } else if (std.mem.eql(u8, name, "shared-twice")) {
        var owner = try S.create(std.heap.page_allocator, 1);
        var other = owner.retain();
        owner.release();
        // glint-ignore: A003 -- design: the deliberate second release the checked builds stop on; an isolated child process runs it
        owner.release();
        other.release();
    } else if (std.mem.eql(u8, name, "teardown-held")) {
        var owner = a.Guarded(u64).init(1);
        var held = owner.acquire();
        defer held.deinit();
        std.mem.doNotOptimizeAway(owner.teardown());
    } else return error.UnknownCase;
}
