const std = @import("std");
const builtin = @import("builtin");
const shake = @import("shakedown");
const a = @import("../root.zig");
const Io = std.Io;
const t = std.testing;

test "A6 blocking acquisition cancel grants nothing and preserves immediate semantics" {
    const fio = try shake.FaultIo.init(t.allocator, t.io, .{ .plan = &.{
        .{ .at = .{ .nth = .{ .call = .futexWait, .n = 1 } }, .fault = .cancel },
    } });
    defer fio.deinit();
    var owner = a.BlockingGuarded(u32).init(7);
    var held = try owner.acquire(fio.io());
    try t.expectEqual(@as(u64, 0), fio.count(.checkCancel));
    try t.expect(owner.tryAcquire() == null);
    try t.expectError(error.Canceled, owner.acquire(fio.io()));
    held.value().* = 9;
    held.deinit(fio.io());
    var next = owner.tryAcquire().?;
    try t.expectEqual(@as(u32, 9), next.value().*);
    next.deinit(fio.io());
}

test "A6 rw all-build reader writer admission and cancel rollback" {
    const fio = try shake.FaultIo.init(t.allocator, t.io, .{ .plan = &.{
        .{ .at = .{ .nth = .{ .call = .futexWait, .n = 1 } }, .fault = .cancel },
        .{ .at = .{ .nth = .{ .call = .futexWait, .n = 2 } }, .fault = .cancel },
    } });
    defer fio.deinit();
    const io = fio.io();
    const R = a.RwGuarded(u32);
    try t.expectError(error.InvalidLimit, R.initLimit(0, R.maximum_admission + 1));
    var owner = try R.initLimit(42, 2);
    var read1 = try owner.read(io);
    var read2 = (try owner.tryRead(io)).?;
    try t.expectError(error.AdmissionLimit, owner.write(io));
    try t.expectError(error.AdmissionLimit, owner.read(io));
    read2.deinit(io);
    try t.expect((try owner.tryWrite(io)) == null);
    try t.expectError(error.Canceled, owner.write(io));
    try t.expectEqual(@as(usize, 1), owner.admitted.load(.monotonic));
    read1.deinit(io);
    var write = try owner.writeUncancelable(io);
    write.value().* = 43;
    try t.expect((try owner.tryRead(io)) == null);
    try t.expectError(error.Canceled, owner.read(io));
    try t.expectEqual(@as(usize, 1), owner.admitted.load(.monotonic));
    write.deinit(io);
    var read3 = try owner.readUncancelable(io);
    try t.expectEqual(@as(u32, 43), read3.value().*);
    read3.deinit(io);
    try t.expectEqual(@as(usize, 0), owner.admitted.load(.monotonic));
}

const WaitState = struct {
    owner: a.BlockingGuarded(u32) = .init(0),
    changed: a.Condition = .initLimit(2),
    started: Io.Event = .unset,
    fn wait(self: *WaitState, io: Io) a.Condition.WaitError!u32 {
        var held = try self.owner.acquire(io);
        defer held.deinit(io);
        self.started.set(io);
        const deadline = (Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } }).toDeadline(io);
        while (held.value().* == 0) try self.changed.wait(io, &held, deadline);
        return held.value().*;
    }
    fn signal(self: *WaitState, io: Io) !void {
        var future = try io.concurrent(wait, .{ self, io });
        try self.started.wait(io);
        var held = try self.owner.acquire(io);
        held.value().* = 11;
        self.changed.signal(io);
        held.deinit(io);
        try t.expectEqual(@as(u32, 11), try future.await(io));
        try t.expectEqual(@as(usize, 0), self.changed.count);
    }
    fn cancel(self: *WaitState, io: Io) !void {
        var future = try io.concurrent(wait, .{ self, io });
        try self.started.wait(io);
        var held = try self.owner.acquire(io);
        held.deinit(io);
        try t.expectError(error.Canceled, future.cancel(io));
        try t.expectEqual(@as(usize, 0), self.changed.count);
        held = self.owner.tryAcquire().?;
        held.deinit(io);
    }
    fn timeout(self: *WaitState, io: Io) !void {
        try t.expectError(error.Timeout, self.wait(io));
        try t.expectEqual(@as(usize, 0), self.changed.count);
        var held = self.owner.tryAcquire().?;
        held.deinit(io);
    }
};
test "A6 condition simulated signal cancel deadline and spurious wake cleanup" {
    for (0..8) |seed| {
        inline for (.{ WaitState.signal, WaitState.cancel, WaitState.timeout }) |run| {
            const sim = try shake.Sim.init(t.allocator, .{ .seed = seed, .yield_per_million = 250000, .spurious_wake_per_million = 300000 });
            defer sim.deinit();
            var state: WaitState = .{};
            try t.expectEqual(shake.Sim.Outcome.finished, sim.run(run, .{ &state, sim.io() }));
        }
    }
}

test "A6 condition waiter ceiling preserves held guard" {
    var owner = a.BlockingGuarded(u32).init(1);
    var changed = a.Condition.initLimit(0);
    var held = try owner.acquire(t.io);
    defer held.deinit(t.io);
    try t.expectError(error.WaiterLimit, changed.wait(t.io, &held, .none));
    try t.expectEqual(@as(u32, 1), held.value().*);
    try t.expect(owner.tryAcquire() == null);
}

const CancelSignal = struct {
    condition: *a.Condition,
    const L = shake.Layer(CancelSignal, .{ .futexWait = futex });
    fn futex(userdata: ?*anyopaque, _: *const u32, _: u32, _: Io.Timeout) Io.Cancelable!void {
        const layer = L.of(userdata);
        layer.state.condition.signal(layer.base);
        return error.Canceled;
    }
};
test "A6 condition cancellation wins raced signal and returns with guard" {
    var owner = a.BlockingGuarded(u32).init(3);
    var changed = a.Condition.init();
    var layer = CancelSignal.L.init(t.io, .{ .condition = &changed });
    var held = try owner.acquire(layer.io());
    defer held.deinit(layer.io());
    try t.expectError(error.Canceled, changed.wait(layer.io(), &held, .none));
    try t.expectEqual(@as(usize, 0), changed.count);
    try t.expectEqual(@as(u32, 3), held.value().*);
    try t.expect(owner.tryAcquire() == null);
}

const OnceValue = struct { a: u64, b: u64 };
fn initialize(_: Io, counter: *usize, destination: *OnceValue) error{BadInit}!void {
    counter.* += 1;
    if (counter.* == 1) return error.BadInit;
    destination.* = .{ .a = 123, .b = 456 };
}
fn cleanupValue(_: *OnceValue) void {}
test "A6 once failure retries stable destination and only publishes complete owner" {
    var once = a.Once(OnceValue).init();
    defer once.deinit(cleanupValue);
    var task: a.InitContext = .{};
    var calls: usize = 0;
    try t.expect(once.get() == null);
    try t.expectError(error.BadInit, once.getOrInit(t.io, &task, &calls, initialize));
    try t.expect(once.get() == null);
    const value = try once.getOrInit(t.io, &task, &calls, initialize);
    try t.expect(value == &once.data);
    try t.expectEqual(@as(u64, 456), value.b);
    try t.expect(value == try once.getOrInit(t.io, &task, &calls, initialize));
    try t.expectEqual(@as(usize, 2), calls);
}
const OnceRace = struct {
    once: a.Once(OnceValue) = .initLimit(4),
    started: Io.Event = .unset,
    finish: Io.Event = .unset,
    calls: usize = 0,
    fn initialize(io: Io, self: *OnceRace, destination: *OnceValue) Io.Cancelable!void {
        self.calls += 1;
        destination.a = 123;
        self.started.set(io);
        try self.finish.wait(io);
        destination.b = 456;
    }
    fn get(self: *OnceRace, io: Io) !*const OnceValue {
        var task: a.InitContext = .{};
        return self.once.getOrInit(io, &task, self, OnceRace.initialize);
    }
    fn main(self: *OnceRace, io: Io) !void {
        var winner = try io.concurrent(get, .{ self, io });
        try self.started.wait(io);
        try t.expect(self.once.get() == null);
        var waiter = try io.concurrent(get, .{ self, io });
        try io.sleep(.fromNanoseconds(1), .awake);
        try t.expectError(error.Canceled, waiter.cancel(io));
        try t.expect(self.once.get() == null);
        self.finish.set(io);
        const published = try winner.await(io);
        try t.expectEqual(@as(u64, 456), published.b);
        try t.expectEqual(@as(usize, 1), self.calls);
        try t.expectEqual(@as(usize, 0), self.once.changed.count);
    }
};
test "A6 once simulated waiting cancel never cancels initializer or publishes partial" {
    for (0..8) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .seed = seed });
        defer sim.deinit();
        var state: OnceRace = .{};
        defer state.once.deinit(cleanupValue);
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(OnceRace.main, .{ &state, sim.io() }));
    }
}

test "A6 logical-task rank checks before base lock waiting and reservation across condition" {
    const O = a.Order(&.{ .{ .name = "root" }, .{ .name = "child", .after = &.{0} }, .{ .name = "other" } });
    var ctx: O.Context = .{};
    var low = O.Ordered(a.BlockingGuarded(u32), 0).init(.init(1));
    var high = O.Ordered(a.BlockingGuarded(u32), 1).init(.init(2));
    var equal = O.Ordered(a.BlockingGuarded(u32), 0).init(.init(3));
    var held = try low.acquireOrdered(t.io, &ctx);
    if (builtin.mode == .debug) {
        try t.expectError(error.SameOwner, ctx.check(&low, 0));
        try t.expectError(error.Unordered, ctx.check(&equal, 0));
        try t.expectError(error.Unordered, ctx.check(&high, 2));
    }
    var child = try high.acquireOrdered(t.io, &ctx);
    try t.expectEqual(@as(u32, 2), child.value().*);
    if (builtin.mode == .debug) try t.expectError(error.Inversion, ctx.check(&equal, 0));
    child.deinit(t.io);
    var condition = a.Condition.initLimit(0);
    try t.expectError(error.WaiterLimit, condition.wait(t.io, &held, .none));
    held.deinit(t.io);
    if (builtin.mode != .debug) try t.expectEqual(@as(usize, 0), @sizeOf(O.Context));
}

test "A6 Confined identity access and explicit synchronized handoff" {
    const first: a.TaskIdentity = @fromBackingInt(@intCast(1));
    const next: a.TaskIdentity = @fromBackingInt(@intCast(2));
    var value = a.Confined(u64).init(first, 7);
    value.value(first).* = 8;
    value.handOff(first, next);
    try t.expectEqual(@as(u64, 8), value.valueConst(next).*);
    if (builtin.mode == .fast or builtin.mode == .small) try t.expectEqual(@sizeOf(u64), @sizeOf(@TypeOf(value)));
}

const Native = struct {
    mutex: a.BlockingGuarded(u64) = .init(0),
    rw: a.RwGuarded(OnceValue) = .init(.{ .a = 0, .b = 0 }),
    once: a.Once(OnceValue) = .init(),
    calls: std.atomic.Value(u32) = .init(0),
    fn initOnce(_: Io, self: *Native, destination: *OnceValue) Io.Cancelable!void {
        _ = self.calls.fetchAdd(1, .monotonic);
        destination.a = 123;
        std.Thread.yield() catch |err| @panic(@errorName(err));
        destination.b = 456;
    }
    fn run(self: *Native, io: Io, index: usize) void {
        var task: a.InitContext = .{};
        for (0..256) |_| {
            var held = self.mutex.acquireUncancelable(io);
            held.value().* += 1;
            held.deinit(io);
            if (index % 2 == 0) {
                var write = self.rw.writeUncancelable(io) catch @panic("unexpected admission limit");
                write.value().a += 1;
                std.Thread.yield() catch |err| @panic(@errorName(err));
                write.value().b += 1;
                write.deinit(io);
            } else {
                var read = self.rw.readUncancelable(io) catch @panic("unexpected admission limit");
                std.debug.assert(read.value().a == read.value().b);
                read.deinit(io);
            }
            const published = self.once.getOrInit(io, &task, self, initOnce) catch @panic("unexpected initializer failure");
            std.debug.assert(published.a == 123);
            std.debug.assert(published.b == 456);
        }
    }
};
test "A6 native publication mutex rw contention and ready Once" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var state: Native = .{};
    defer state.once.deinit(cleanupValue);
    var threads: [8]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try .spawn(.{}, Native.run, .{ &state, t.io, index });
    for (threads) |thread| thread.join();
    var held = try state.mutex.acquire(t.io);
    defer held.deinit(t.io);
    try t.expectEqual(@as(u64, 8 * 256), held.value().*);
    try t.expectEqual(@as(u32, 1), state.calls.load(.monotonic));
}

const AllocationValue = struct {
    gpa: std.mem.Allocator,
    bytes: []u8,
    cleaned: *usize,
    fn cleanup(self: *AllocationValue) void {
        self.gpa.free(self.bytes);
        self.cleaned.* += 1;
        self.* = undefined;
    }
};
const AllocationInit = struct {
    gpa: std.mem.Allocator,
    cleaned: *usize,
    fn initialize(io: Io, self: *AllocationInit, destination: *AllocationValue) (std.mem.Allocator.Error || Io.Cancelable)!void {
        const bytes = try self.gpa.alloc(u8, 16);
        errdefer self.gpa.free(bytes);
        const scratch = try self.gpa.alloc(u8, 8);
        defer self.gpa.free(scratch);
        try io.checkCancel();
        destination.* = .{ .gpa = self.gpa, .bytes = bytes, .cleaned = self.cleaned };
    }
};
fn onceAllocation(gpa: std.mem.Allocator) !void {
    var cleaned: usize = 0;
    var once = a.Once(AllocationValue).init();
    defer once.deinit(AllocationValue.cleanup);
    var task: a.InitContext = .{};
    var context: AllocationInit = .{ .gpa = gpa, .cleaned = &cleaned };
    const result = once.getOrInit(t.io, &task, &context, AllocationInit.initialize) catch |err| {
        try t.expect(once.get() == null);
        try t.expectEqual(@as(usize, 0), cleaned);
        return err;
    };
    try t.expectEqual(@as(usize, 16), result.bytes.len);
}
test "A6 Once every initializer allocation failure leaves empty without partial owner" {
    var no_resize = shake.alloc.NoResize.init(t.allocator);
    try t.checkAllAllocationFailures(no_resize.allocator(), onceAllocation, .{});
}
test "A6 Once canceled initializer cleans all partial acquisitions and retries" {
    const fio = try shake.FaultIo.init(t.allocator, t.io, .{ .plan = &.{
        .{ .at = .{ .nth = .{ .call = .checkCancel, .n = 1 } }, .fault = .cancel },
    } });
    defer fio.deinit();
    var cleaned: usize = 0;
    var once = a.Once(AllocationValue).init();
    defer once.deinit(AllocationValue.cleanup);
    var task: a.InitContext = .{};
    var context: AllocationInit = .{ .gpa = t.allocator, .cleaned = &cleaned };
    try t.expectError(error.Canceled, once.getOrInit(fio.io(), &task, &context, AllocationInit.initialize));
    try t.expect(once.get() == null);
    const result = try once.getOrInit(fio.io(), &task, &context, AllocationInit.initialize);
    try t.expectEqual(@as(usize, 16), result.bytes.len);
    try t.expectEqual(@as(usize, 0), cleaned);
}

const BroadcastState = struct {
    owner: a.BlockingGuarded(u32) = .init(0),
    changed: a.Condition = .initLimit(2),
    started: [2]Io.Event = @splat(.unset),
    fn waiter(self: *BroadcastState, io: Io, index: usize) !void {
        var held = try self.owner.acquire(io);
        defer held.deinit(io);
        self.started[index].set(io);
        while (held.value().* == 0) try self.changed.wait(io, &held, .none);
    }
    fn main(self: *BroadcastState, io: Io) !void {
        var first = try io.concurrent(waiter, .{ self, io, 0 });
        var second = try io.concurrent(waiter, .{ self, io, 1 });
        for (&self.started) |*event| try event.wait(io);
        var held = try self.owner.acquire(io);
        try t.expectEqual(@as(usize, 2), self.changed.count);
        try t.expectError(error.WaiterLimit, self.changed.wait(io, &held, .none));
        held.value().* = 1;
        self.changed.broadcast(io);
        held.deinit(io);
        try first.await(io);
        try second.await(io);
        try t.expectEqual(@as(usize, 0), self.changed.count);
    }
};
test "A6 condition broadcast wakes every registered waiter and cap refuses excess" {
    for (0..8) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .seed = seed, .yield_per_million = 150000 });
        defer sim.deinit();
        var state: BroadcastState = .{};
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(BroadcastState.main, .{ &state, sim.io() }));
    }
}

const OnceLimit = struct {
    race: OnceRace = .{ .once = .initLimit(0) },
    fn main(self: *OnceLimit, io: Io) !void {
        var winner = try io.concurrent(OnceRace.get, .{ &self.race, io });
        try self.race.started.wait(io);
        var task: a.InitContext = .{};
        try t.expectError(error.WaiterLimit, self.race.once.getOrInit(io, &task, &self.race, OnceRace.initialize));
        try t.expect(self.race.once.get() == null);
        self.race.finish.set(io);
        try t.expectEqual(@as(u64, 456), (try winner.await(io)).b);
    }
};
test "A6 Once finite waiting ceiling does not disturb initializer" {
    const sim = try shake.Sim.init(t.allocator, .{});
    defer sim.deinit();
    var state: OnceLimit = .{};
    defer state.race.once.deinit(cleanupValue);
    try t.expectEqual(shake.Sim.Outcome.finished, sim.run(OnceLimit.main, .{ &state, sim.io() }));
}

fn canceledWinner(state: *OnceRace, io: Io) !void {
    var winner = try io.concurrent(OnceRace.get, .{ state, io });
    try state.started.wait(io);
    var waiter = try io.concurrent(OnceRace.get, .{ state, io });
    try io.sleep(.fromNanoseconds(1), .awake);
    try t.expectError(error.Canceled, winner.cancel(io));
    state.finish.set(io);
    try t.expectEqual(@as(u64, 456), (try waiter.await(io)).b);
    try t.expectEqual(@as(usize, 2), state.calls);
    try t.expectEqual(@as(usize, 0), state.once.changed.count);
}
test "A6 canceled initializer wakes existing waiters to retry publication" {
    for (0..4) |seed| {
        const sim = try shake.Sim.init(t.allocator, .{ .seed = seed });
        defer sim.deinit();
        var state: OnceRace = .{};
        defer state.once.deinit(cleanupValue);
        try t.expectEqual(shake.Sim.Outcome.finished, sim.run(canceledWinner, .{ &state, sim.io() }));
    }
}
