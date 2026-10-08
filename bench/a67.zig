//! Paired A6/A7 ReleaseFast A/B; ABBA/BAAB blocks on the current shared host.
const std = @import("std");
const a = @import("aegis");
const c = @import("a67");
const shake = @import("shakedown");
const Io = std.Io;
const samples = 16;
const rounds = 100000;
const names = [_][]const u8{ "mutex", "rw_read", "rw_write", "once_ready", "once_cold", "condition", "array", "queue", "buffer", "ring_buffer", "limit", "budget", "owned", "must_use", "confined", "ordered" };
const State = struct {
    base_mutex: c.DirectMutex = .{ .data = 0 },
    wrap_mutex: a.BlockingGuarded(u64) = .init(0),
    base_rw: c.DirectRw = .{ .data = 0 },
    wrap_rw: a.RwGuarded(u64) = .init(0),
    base_once: c.DirectOnce = .{},
    wrap_once: a.Once(u64) = .init(),
    base_changed: a.Condition = .initLimit(0),
    wrap_changed: a.Condition = .initLimit(0),
    base_array: c.DirectArray = .{},
    wrap_array: a.bounded.Array(u64, 3) = .init,
    base_queue: c.DirectQueue = .{},
    wrap_queue: a.bounded.Queue(u64, 3) = .init,
    base_budget: c.DirectBudget = .{ .maximum = 1024 },
    wrap_budget: a.bounded.Budget(u64) = .init(1024),
    base_memory: [3]u64 = undefined,
    wrap_memory: [3]u64 = undefined,
    base_buffer: c.DirectBuffer = undefined,
    wrap_buffer: a.bounded.Buffer(u64) = undefined,
    base_ring: c.DirectRingBuffer = undefined,
    wrap_ring: a.bounded.RingBuffer(u64) = undefined,
    base_confined: c.DirectConfined = .{ .data = 0, .owner = if (c.checked) @fromBackingInt(@intCast(1)) else {} },
    wrap_confined: a.Confined(u64) = .init(@fromBackingInt(@intCast(1)), 0),
    wrap_ordered: c.Ordered = .init(.init(0)),
    sequence: u64 = 0,
    output: u64 = 0,
    fn init(self: *State) void {
        self.* = .{};
        self.base_buffer = .{ .storage = &self.base_memory, .gpa = null, .maximum = 3 };
        self.wrap_buffer = .initBuffer(&self.wrap_memory);
        self.base_ring = .{ .storage = &self.base_memory, .gpa = null, .maximum = 3 };
        self.wrap_ring = a.bounded.RingBuffer(u64).initBuffer(&self.wrap_memory) catch @panic("nonzero storage");
        self.base_once.data = 42;
        self.base_once.state.store(.ready, .release);
        self.wrap_once.data = 42;
        self.wrap_once.state.store(.ready, .release);
    }
};
const Operation = *const fn (Io, *State) u64;
fn operation(comptime name: []const u8, comptime wrapped: bool) Operation {
    return struct {
        fn run(io: Io, state: *State) align(64) u64 {
            state.sequence +%= 1;
            const input = state.sequence;
            if (comptime std.mem.eql(u8, name, "mutex")) return c.mutex(wrapped, io, if (wrapped) &state.wrap_mutex else &state.base_mutex) catch 0;
            if (comptime std.mem.eql(u8, name, "rw_read")) return c.rw(wrapped, false, io, if (wrapped) &state.wrap_rw else &state.base_rw) catch 0;
            if (comptime std.mem.eql(u8, name, "rw_write")) return c.rw(wrapped, true, io, if (wrapped) &state.wrap_rw else &state.base_rw) catch 0;
            if (comptime std.mem.eql(u8, name, "once_ready")) return c.onceReady(wrapped, if (wrapped) &state.wrap_once else &state.base_once).?.*;
            if (comptime std.mem.eql(u8, name, "once_cold")) {
                const owner = if (wrapped) &state.wrap_once else &state.base_once;
                owner.state.store(.empty, .monotonic);
                return (c.onceCold(wrapped, io, owner, input) catch return 0).*;
            }
            if (comptime std.mem.eql(u8, name, "condition")) return c.condition(wrapped, io, if (wrapped) &state.wrap_changed else &state.base_changed, if (wrapped) &state.wrap_mutex else &state.base_mutex, .none) catch |err| @intFromError(err);
            if (comptime std.mem.eql(u8, name, "array")) {
                const owner = if (wrapped) &state.wrap_array else &state.base_array;
                const admitted = c.array(wrapped, owner, input);
                if (!admitted) owner.used = 0;
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "queue")) {
                const owner = if (wrapped) &state.wrap_queue else &state.base_queue;
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
                const owner = if (wrapped) &state.wrap_buffer else &state.base_buffer;
                const admitted = c.buffer(wrapped, owner, input);
                if (!admitted) owner.used = 0;
                return @intFromBool(admitted);
            }
            if (comptime std.mem.eql(u8, name, "ring_buffer")) {
                const owner = if (wrapped) &state.wrap_ring else &state.base_ring;
                const admitted = c.ringBuffer(wrapped, owner, input);
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
            if (comptime std.mem.eql(u8, name, "limit")) return @intFromBool(c.limit(wrapped, 1024, input % 2048));
            if (comptime std.mem.eql(u8, name, "budget")) return @intFromBool(c.budget(wrapped, if (wrapped) &state.wrap_budget else &state.base_budget, input % 2048, input % 2048));
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
            if (comptime std.mem.eql(u8, name, "confined")) return c.confined(wrapped, if (wrapped) &state.wrap_confined else &state.base_confined, @fromBackingInt(@intCast(1)));
            if (comptime std.mem.eql(u8, name, "ordered")) return c.ordered(wrapped, io, if (wrapped) &state.wrap_ordered else &state.base_mutex) catch 0;
            unreachable;
        }
    }.run;
}
const Pair = struct { base: f64, wrap: f64 };
noinline fn measure(io: Io, op: Operation, count: usize) f64 {
    var state: State = undefined;
    state.init();
    var sum: u64 = 0;
    const start = Io.Clock.awake.now(io);
    for (0..count) |_| sum +%= op(io, &state);
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
        var b: State = undefined;
        var w: State = undefined;
        b.init();
        w.init();
        for (0..8) |_| if (base(init.io, &b) != wrap(init.io, &w)) return error.BaselineMismatch;
        if (smoke) {
            _ = measure(init.io, base, 2);
            _ = measure(init.io, wrap, 2);
        } else {
            _ = measure(init.io, base, rounds / 4);
            _ = measure(init.io, wrap, rounds / 4);
            var pairs: [samples]Pair = undefined;
            for (&pairs, 0..) |*pair, i| {
                if (i % 2 == 0) {
                    const b1 = measure(init.io, base, rounds);
                    const w1 = measure(init.io, wrap, rounds);
                    const w2 = measure(init.io, wrap, rounds);
                    const b2 = measure(init.io, base, rounds);
                    pair.* = .{ .base = (b1 + b2) / 2, .wrap = (w1 + w2) / 2 };
                } else {
                    const w1 = measure(init.io, wrap, rounds);
                    const b1 = measure(init.io, base, rounds);
                    const b2 = measure(init.io, base, rounds);
                    const w2 = measure(init.io, wrap, rounds);
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
