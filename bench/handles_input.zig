//! Interleaved ABBA/BAAB measurements; identical required checks and capacity.
const std = @import("std");
const shake = @import("shakedown");
const c = @import("safety");
pub const samples = 32;
const count = 1_000_000;
pub const Pair = struct { baseline: f64, wrapper: f64 };
const names = [_][]const u8{ "sequential", "random", "churn", "index", "parse", "parse_failure", "context", "diagnostics_null", "diagnostics_enabled", "dense" };
fn Owner(comptime wrapped: bool) type {
    return if (wrapped) c.Pool else c.Direct;
}
fn Diagnostic(comptime wrapped: bool) type {
    return if (wrapped) c.Context else c.DirectContext;
}
fn slotStorage(comptime wrapped: bool, slots: []Owner(wrapped).Slot) Owner(wrapped) {
    for (slots, 0..) |*slot, i| slot.* = .{ .state = .live, .value = @intCast(i) }; // safe: benchmark capacity is 256
    return .{ .slots = slots, .instance = .{ .namespace = 17, .serial = 1 }, .free_head = std.math.maxInt(usize), .len = slots.len };
}
noinline fn measure(comptime name: []const u8, comptime wrapped: bool, io: std.Io, rounds: usize) f64 {
    var slots: [256]Owner(wrapped).Slot = undefined;
    var owner = slotStorage(wrapped, &slots);
    var keys: [256]c.Key = undefined;
    for (&keys, 0..) |*key, i| key.* = .{ .instance = owner.instance, .index = i, .generation = 1 };
    var values: [256]u32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i); // safe: capacity is 256
    var ctx: Diagnostic(wrapped) = .{};
    var input: [34]u8 = @splat(7);
    input[1] = if (comptime std.mem.eql(u8, name, "parse_failure")) 255 else 32;
    var state: u64 = 1;
    var sum: u64 = 0;
    std.mem.doNotOptimizeAway(&owner);
    const start = std.Io.Clock.awake.now(io);
    for (0..rounds) |i| {
        state = state *% 6364136223846793005 +% 1;
        const index: usize = @intCast(if (comptime std.mem.eql(u8, name, "random")) (state >> 24) & 255 else i & 255); // safe: both positions are masked to 0..255
        if (comptime std.mem.eql(u8, name, "sequential") or std.mem.eql(u8, name, "random")) {
            sum +%= if (wrapped) c.wrapperHandleGet(&owner, &keys[index]) else c.baselineHandleGet(&owner, &keys[index]);
        } else if (comptime std.mem.eql(u8, name, "churn")) {
            var value: u32 = undefined;
            const removed = if (wrapped) c.wrapperHandleRemove(&owner, &keys[index], &value) else c.baselineHandleRemove(&owner, &keys[index], &value);
            std.debug.assert(removed);
            const generation = if (wrapped) c.wrapperHandleInsert(&owner, &value) else c.baselineHandleInsert(&owner, &value);
            keys[index].generation = generation;
            sum +%= generation;
        } else if (comptime std.mem.eql(u8, name, "index")) {
            const raw: u32 = @intCast(index); // safe: masked position is 0..255
            sum +%= if (wrapped) c.wrapperHandleIndex(raw, &values, values.len) else c.baselineHandleIndex(raw, &values, values.len);
        } else if (comptime std.mem.startsWith(u8, name, "parse")) {
            input[0] = @truncate(i); // safe: synthetic public byte cycles
            sum +%= if (wrapped) c.wrapperInputParse(&input, input.len, 64) else c.baselineInputParse(&input, input.len, 64);
        } else if (comptime std.mem.eql(u8, name, "context")) {
            ctx.len = i & 7; // Includes full/truncated contexts, with the same public limit.
            if (wrapped) c.wrapperContextPush(&ctx, 1, @truncate(i), 2) else c.baselineContextPush(&ctx, 1, @truncate(i), 2); // safe: public numeric offset cycles
            sum +%= ctx.len;
        } else if (comptime std.mem.startsWith(u8, name, "diagnostics")) {
            input[1] = if (i & 1 == 0) 32 else 255;
            ctx.len = 0;
            const ptr = if (comptime std.mem.eql(u8, name, "diagnostics_null")) null else &ctx;
            sum +%= if (wrapped) c.wrapperInputDiagnostics(&input, input.len, 64, ptr) else c.baselineInputDiagnostics(&input, input.len, 64, ptr);
        } else if (comptime std.mem.eql(u8, name, "dense")) {
            values[index] +%= 1;
            sum +%= if (wrapped) c.wrapperDenseSum(&values, values.len) else c.baselineDenseSum(&values, values.len);
        }
    }
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(sum);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(rounds));
}
pub fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    const middle = values.len / 2;
    return if (values.len % 2 == 0) (values[middle - 1] + values[middle]) / 2 else values[middle];
}
pub fn report(gpa: std.mem.Allocator, writer: *std.Io.Writer, name: []const u8, pairs: []const Pair) !void {
    var base: [samples]f64 = undefined;
    var wrap: [samples]f64 = undefined;
    var ratios: [samples]f64 = undefined;
    for (pairs, 0..) |pair, i| {
        base[i] = pair.baseline;
        wrap[i] = pair.wrapper;
        ratios[i] = pair.wrapper / pair.baseline;
    }
    const bs = try shake.bench.statistics(gpa, &base);
    const ws = try shake.bench.statistics(gpa, &wrap);
    var random = std.Random.DefaultPrng.init(0xa8a9);
    var bootstrap: [10_000]f64 = undefined;
    for (&bootstrap) |*estimate| {
        var draws: [samples]f64 = undefined;
        for (&draws) |*draw| draw.* = ratios[random.random().uintLessThan(usize, samples)];
        estimate.* = median(&draws);
    }
    std.mem.sort(f64, &bootstrap, {}, std.sort.asc(f64));
    std.mem.sort(f64, &base, {}, std.sort.asc(f64));
    std.mem.sort(f64, &wrap, {}, std.sort.asc(f64));
    try writer.print("{s},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.9},{d:.9},{d:.6},{d:.6},{d:.6},{d:.6}\n", .{ name, bs.median, ws.median, bs.best, ws.best, base[30], wrap[30], bs.p99, ws.p99, bootstrap[250], bootstrap[9749], base[0], base[31], wrap[0], wrap[31] });
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var storage: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &storage);
    if (!smoke) try out.interface.writeAll("workload,baseline_ns,wrapper_ns,baseline_best,wrapper_best,baseline_p95,wrapper_p95,baseline_p99,wrapper_p99,ratio95_low,ratio95_high,baseline_min,baseline_max,wrapper_min,wrapper_max\n");
    inline for (names) |name| {
        if (smoke) {
            _ = measure(name, false, init.io, 16);
            _ = measure(name, true, init.io, 16);
        } else {
            _ = measure(name, false, init.io, count / 5);
            _ = measure(name, true, init.io, count / 5);
            var pairs: [samples]Pair = undefined;
            for (&pairs, 0..) |*pair, i| {
                if (i % 2 == 0) {
                    const b1 = measure(name, false, init.io, count);
                    const w1 = measure(name, true, init.io, count);
                    const w2 = measure(name, true, init.io, count);
                    const b2 = measure(name, false, init.io, count);
                    pair.* = .{ .baseline = (b1 + b2) / 2, .wrapper = (w1 + w2) / 2 };
                } else {
                    const w1 = measure(name, true, init.io, count);
                    const b1 = measure(name, false, init.io, count);
                    const b2 = measure(name, false, init.io, count);
                    const w2 = measure(name, true, init.io, count);
                    pair.* = .{ .baseline = (b1 + b2) / 2, .wrapper = (w1 + w2) / 2 };
                }
            }
            try report(init.gpa, &out.interface, name, &pairs);
        }
    }
    try out.interface.flush();
}
