//! Paired A6/A7 ReleaseFast A/B; ABBA/BAAB blocks on the current shared host.
const std = @import("std");
const a = @import("aegis");
const c = @import("a67");
const shake = @import("shakedown");
const builtin = @import("builtin");
const Io = std.Io;
const samples = 16;
const rounds = 100000;
const names = [_][]const u8{ "mutex", "rw_read", "rw_write", "once_ready", "once_cold", "condition", "array", "queue", "buffer", "ring_buffer", "limit", "budget", "owned", "must_use", "confined", "ordered" };
fn State(comptime wrapped: bool) type {
    return struct {
        const Self = @This();
        mutex: if (wrapped) a.BlockingGuarded(u64) else c.DirectMutex = if (wrapped) .init(0) else .{ .data = 0 },
        rw: if (wrapped) a.RwGuarded(u64) else c.DirectRw = if (wrapped) .init(0) else .{ .data = 0 },
        once: if (wrapped) a.Once(u64) else c.DirectOnce = if (wrapped) .init() else .{},
        changed: a.Condition = .initLimit(0),
        array: if (wrapped) a.bounded.Array(u64, 3) else c.DirectArray = if (wrapped) .init else .{},
        queue: if (wrapped) a.bounded.Queue(u64, 3) else c.DirectQueue = if (wrapped) .init else .{},
        budget: if (wrapped) a.bounded.Budget(u64) else c.DirectBudget = if (wrapped) .init(1024) else .{ .maximum = 1024 },
        memory: [3]u64 = undefined,
        buffer: if (wrapped) a.bounded.Buffer(u64) else c.DirectBuffer = undefined,
        ring: if (wrapped) a.bounded.RingBuffer(u64) else c.DirectRingBuffer = undefined,
        confined: if (wrapped) a.Confined(u64) else c.DirectConfined = if (wrapped) .init(@fromBackingInt(@intCast(1)), 0) else .{ .data = 0, .owner = if (c.checked) @fromBackingInt(@intCast(1)) else {} },
        ordered: if (wrapped) c.Ordered else c.DirectMutex = if (wrapped) .init(.init(0)) else .{ .data = 0 },
        sequence: u64 = 0,
        output: u64 = 0,
        fn init(self: *Self) void {
            self.* = .{};
            self.buffer = if (wrapped) .initBuffer(&self.memory) else .{ .storage = &self.memory, .gpa = null, .maximum = 3 };
            self.ring = if (wrapped) (a.bounded.RingBuffer(u64).initBuffer(&self.memory) catch @panic("nonzero storage")) else .{ .storage = &self.memory, .gpa = null, .maximum = 3 };
            self.once.data = 42;
            self.once.state.store(.ready, .release);
        }
    };
}
comptime {
    if (builtin.mode == .fast) {
        std.debug.assert(@sizeOf(State(false)) == @sizeOf(State(true)));
        for (@typeInfo(State(false)).@"struct".field_names) |name| std.debug.assert(@offsetOf(State(false), name) == @offsetOf(State(true), name));
    }
}
const Operation = *const fn (Io, *anyopaque) u64;
fn operation(comptime name: []const u8, comptime wrapped: bool) Operation {
    return struct {
        fn run(io: Io, opaque_state: *anyopaque) align(64) u64 {
            const state: *State(wrapped) = @ptrCast(@alignCast(opaque_state)); // safe: measure/validation passes a live matched State(wrapped)
            state.sequence +%= 1;
            const input = state.sequence;
            if (comptime std.mem.eql(u8, name, "mutex")) return c.mutex(wrapped, io, &state.mutex) catch 0;
            if (comptime std.mem.eql(u8, name, "rw_read")) return c.rw(wrapped, false, io, &state.rw) catch 0;
            if (comptime std.mem.eql(u8, name, "rw_write")) return c.rw(wrapped, true, io, &state.rw) catch 0;
            if (comptime std.mem.eql(u8, name, "once_ready")) return c.onceReady(wrapped, &state.once).?.*;
            if (comptime std.mem.eql(u8, name, "once_cold")) {
                const owner = &state.once;
                owner.state.store(.empty, .monotonic);
                return (c.onceCold(wrapped, io, owner, input) catch return 0).*;
            }
            if (comptime std.mem.eql(u8, name, "condition")) return c.condition(wrapped, io, &state.changed, &state.mutex, .none) catch |err| @intFromError(err);
            if (comptime std.mem.eql(u8, name, "array")) {
                const owner = &state.array;
                const admitted = c.array(wrapped, owner, input);
                if (!admitted) owner.used = 0;
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "queue")) {
                const owner = &state.queue;
                const admitted = c.queue(wrapped, owner, input);
                if (owner.used == 3) {
                    var out: u64 = undefined;
                    if (wrapped) owner.pop(&out) catch @panic("live head") else {
                        out = owner.storage[owner.head];
                        owner.head = if (owner.head == 2) 0 else owner.head + 1;
                        owner.used -= 1;
                    }
                    return out;
                }
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "buffer")) {
                const owner = &state.buffer;
                const admitted = c.buffer(wrapped, owner, input);
                if (!admitted) owner.used = 0;
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "ring_buffer")) {
                const owner = &state.ring;
                const admitted = c.ringBuffer(wrapped, owner, input);
                if (owner.used == 3) {
                    var out: u64 = undefined;
                    if (wrapped) owner.pop(&out) catch @panic("live head") else {
                        out = owner.storage[owner.head];
                        owner.head = if (owner.head == owner.storage.len - 1) 0 else owner.head + 1;
                        owner.used -= 1;
                    }
                    return out;
                }
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "limit")) return @intFromBool(c.limit(wrapped, 1024, input % 2048));
            if (comptime std.mem.eql(u8, name, "budget")) return @intFromBool(c.budget(wrapped, &state.budget, input % 2048, input % 2048));
            if (comptime std.mem.eql(u8, name, "owned")) {
                const payload: c.Payload = .{ .output = &state.output, .value = input };
                if (wrapped) {
                    var owner = c.Owned.init(payload);
                    c.owned(true, &owner, input % 2 == 0);
                } else {
                    var owner = payload;
                    c.owned(false, &owner, input % 2 == 0);
                }
                return state.output;
            }
            if (comptime std.mem.eql(u8, name, "must_use")) {
                var destination: u64 = undefined;
                if (wrapped) {
                    var owner = c.MustUse.init(input);
                    c.mustUse(true, &owner, &destination);
                } else {
                    var owner = input;
                    c.mustUse(false, &owner, &destination);
                }
                return destination;
            }
            if (comptime std.mem.eql(u8, name, "confined")) return c.confined(wrapped, &state.confined, @fromBackingInt(@intCast(1)));
            if (comptime std.mem.eql(u8, name, "ordered")) return c.ordered(wrapped, io, &state.ordered) catch 0;
            unreachable;
        }
    }.run;
}
const Pair = struct { base: f64, wrap: f64 };
noinline fn measure(comptime wrapped: bool, io: Io, op: Operation, count: usize) f64 {
    var state: State(wrapped) = undefined;
    state.init();
    return measureOperations(io, op, &state, count);
}
// One timed loop for both sides: distinct generic instantiations otherwise
// place identical loops at different instruction offsets on the shared host.
noinline fn measureOperations(io: Io, op: Operation, state: *anyopaque, count: usize) f64 {
    var sum: u64 = 0;
    const start = Io.Clock.awake.now(io);
    for (0..count) |_| sum +%= op(io, state);
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(sum);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}
fn median(v: []f64) f64 {
    std.mem.sort(f64, v, {}, std.sort.asc(f64));
    return (v[v.len / 2 - 1] + v[v.len / 2]) / 2;
}
fn report(gpa: std.mem.Allocator, out: *Io.Writer, name: []const u8, pairs: []const Pair) !void {
    var base: [samples]f64 = undefined;
    var wrap: [samples]f64 = undefined;
    var ratio: [samples]f64 = undefined;
    for (pairs, 0..) |pair, i| {
        base[i] = pair.base;
        wrap[i] = pair.wrap;
        ratio[i] = pair.wrap / pair.base;
    }
    const bs = try shake.bench.statistics(gpa, &base);
    const ws = try shake.bench.statistics(gpa, &wrap);
    const bm = bs.median;
    const wm = ws.median;
    const rm = median(&ratio);
    std.mem.sort(f64, &base, {}, std.sort.asc(f64));
    std.mem.sort(f64, &wrap, {}, std.sort.asc(f64));
    var prng = std.Random.DefaultPrng.init(0xa67);
    var bootstrap: [10000]f64 = undefined;
    for (&bootstrap) |*r| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*x| x.* = ratio[prng.random().uintLessThan(usize, samples)];
        r.* = median(&draw);
    }
    std.mem.sort(f64, &bootstrap, {}, std.sort.asc(f64));
    try out.print("summary,{s},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6}\n", .{ name, bm, wm, rm, bootstrap[250], bootstrap[9749], base[0], wrap[0], base[15], wrap[15], base[0], base[15], wrap[0], wrap[15] });
    for (pairs, 0..) |pair, i| try out.print("pair,{s},{d},{d:.6},{d:.6}\n", .{ name, i, pair.base, pair.wrap });
}
fn Contended(comptime wrapped: bool, comptime rw: bool) type {
    const Owner = if (rw) (if (wrapped) a.RwGuarded(u64) else c.DirectRw) else (if (wrapped) a.BlockingGuarded(u64) else c.DirectMutex);
    return struct {
        const Self = @This();
        owner: Owner,
        io: Io,
        start: Io.Event = .unset,
        results: [8]u64 = @splat(0),
        count: usize,
        fn worker(self: *Self, index: usize) void {
            self.start.waitUncancelable(self.io);
            var sum: u64 = 0;
            for (0..self.count) |_| {
                const value = if (rw) (if (index == 0) c.rw(wrapped, true, self.io, &self.owner) else c.rw(wrapped, false, self.io, &self.owner)) else c.mutex(wrapped, self.io, &self.owner);
                sum +%= value catch @panic("benchmark acquisition failed");
            }
            self.results[index] = sum;
        }
    };
}
fn contention(comptime wrapped: bool, comptime rw: bool, io: Io, workers: usize, count: usize) !f64 {
    const C = Contended(wrapped, rw);
    var context: C = .{ .owner = if (wrapped) .init(0) else .{ .data = 0 }, .io = io, .count = count };
    var threads: [8]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        context.start.set(io);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (threads[0..workers], 0..) |*thread, index| {
        thread.* = try .spawn(.{}, C.worker, .{ &context, index });
        spawned += 1;
    }
    const start = Io.Clock.awake.now(io);
    context.start.set(io);
    for (threads[0..workers]) |thread| thread.join();
    const elapsed = start.durationTo(Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(context.results);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count * workers));
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var out = Io.File.stdout().writerStreaming(init.io, &buffer);
    inline for (names) |name| {
        const base = operation(name, false);
        const wrap = operation(name, true);
        var b: State(false) = undefined;
        var w: State(true) = undefined;
        b.init();
        w.init();
        for (0..8) |_| if (base(init.io, &b) != wrap(init.io, &w)) return error.BaselineMismatch;
        if (smoke) {
            _ = measure(false, init.io, base, 2);
            _ = measure(true, init.io, wrap, 2);
        } else {
            _ = measure(false, init.io, base, rounds / 4);
            _ = measure(true, init.io, wrap, rounds / 4);
            var pairs: [samples]Pair = undefined;
            for (&pairs, 0..) |*pair, i| {
                if (i % 2 == 0) {
                    const b1 = measure(false, init.io, base, rounds);
                    const w1 = measure(true, init.io, wrap, rounds);
                    const w2 = measure(true, init.io, wrap, rounds);
                    const b2 = measure(false, init.io, base, rounds);
                    pair.* = .{ .base = (b1 + b2) / 2, .wrap = (w1 + w2) / 2 };
                } else {
                    const w1 = measure(true, init.io, wrap, rounds);
                    const b1 = measure(false, init.io, base, rounds);
                    const b2 = measure(false, init.io, base, rounds);
                    const w2 = measure(true, init.io, wrap, rounds);
                    pair.* = .{ .base = (b1 + b2) / 2, .wrap = (w1 + w2) / 2 };
                }
            }
            try report(init.gpa, &out.interface, name, &pairs);
        }
    }
    if (!smoke) {
        inline for (.{ false, true }) |rw| {
            for ([_]usize{ 2, 8 }) |workers| {
                _ = try contention(false, rw, init.io, workers, 256);
                _ = try contention(true, rw, init.io, workers, 256);
                var pairs: [samples]Pair = undefined;
                for (&pairs, 0..) |*pair, index| {
                    if (index % 2 == 0) {
                        const b1 = try contention(false, rw, init.io, workers, 4096);
                        const w1 = try contention(true, rw, init.io, workers, 4096);
                        const w2 = try contention(true, rw, init.io, workers, 4096);
                        const b2 = try contention(false, rw, init.io, workers, 4096);
                        pair.* = .{ .base = (b1 + b2) / 2, .wrap = (w1 + w2) / 2 };
                    } else {
                        const w1 = try contention(true, rw, init.io, workers, 4096);
                        const b1 = try contention(false, rw, init.io, workers, 4096);
                        const b2 = try contention(false, rw, init.io, workers, 4096);
                        const w2 = try contention(true, rw, init.io, workers, 4096);
                        pair.* = .{ .base = (b1 + b2) / 2, .wrap = (w1 + w2) / 2 };
                    }
                }
                const name = if (rw) (if (workers == 2) "rw_mixed_2" else "rw_mixed_8") else (if (workers == 2) "mutex_2" else "mutex_8");
                try report(init.gpa, &out.interface, name, &pairs);
            }
        }
    }
    try out.interface.flush();
}
