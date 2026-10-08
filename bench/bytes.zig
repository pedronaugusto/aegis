//! Interleaved full-capacity owner A/B: identical allocator, cleanup and checks.
const std = @import("std");
const bytes = @import("bytes");
const Material = @import("material").Material;
const samples = 64;
const iterations = 500_000;
const Sample = struct { baseline: f64, wrapper: f64 };
const Work = *const fn (std.mem.Allocator, []const u8, usize, usize, bool) usize;
const Row = struct { name: []const u8, live: usize, cap: usize, next: usize = 0, fail: bool = false, oom: bool = false, operation: []const u8 = "cleanup" };
const rows = [_]Row{
    .{ .name = "bytes32", .live = 32, .cap = 32 },
    .{ .name = "bytes48", .live = 48, .cap = 48 },
    .{ .name = "material", .live = @sizeOf(Material), .cap = @sizeOf(Material) },
    .{ .name = "slack", .live = 32, .cap = 256 },
    .{ .name = "resize", .live = 48, .cap = 256, .next = 8, .operation = "resize" },
    .{ .name = "reserve", .live = 48, .cap = 64, .next = 256, .operation = "reserve" },
    .{ .name = "reserveFailure", .live = 48, .cap = 64, .next = 256, .operation = "reserve", .oom = true },
    .{ .name = "parseFailure", .live = 48, .cap = 256, .fail = true },
    .{ .name = "move", .live = 48, .cap = 256, .operation = "move" },
};

const Budget = struct {
    child: std.mem.Allocator,
    remaining: usize,
    fn allocator(self: *Budget) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = std.mem.Allocator.noResize, .remap = std.mem.Allocator.noRemap, .free = free } };
    }
    fn of(ptr: *anyopaque) *Budget {
        return @ptrCast(@alignCast(ptr)); // safe: only paired with *Budget
    }
    fn alloc(ptr: *anyopaque, n: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self = of(ptr);
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        return self.child.rawAlloc(n, alignment, ret);
    }
    fn free(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        of(ptr).child.rawFree(memory, alignment, ret);
    }
};
fn work(comptime name: []const u8, comptime wrapped: bool) Work {
    return struct {
        fn run(gpa: std.mem.Allocator, input: []const u8, cap: usize, next: usize, fail: bool) usize {
            if (comptime std.mem.eql(u8, name, "move")) return bytes.moveConsumer(wrapped, gpa, input, cap, fail) catch 0;
            return bytes.consumer(name, wrapped, gpa, input, cap, next, fail) catch 0;
        }
    }.run;
}
noinline fn measure(io: std.Io, callback: Work, row: Row, rounds: usize) f64 {
    var source: [@sizeOf(Material)]u8 = @splat(0x6d);
    var storage: [8192]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    var budget: Budget = .{ .child = fixed.allocator(), .remaining = 0 };
    var accumulator: usize = 0;
    const start = std.Io.Clock.awake.now(io);
    for (0..rounds) |i| {
        fixed.reset();
        budget.remaining = if (row.oom) 1 else std.math.maxInt(usize);
        source[0] = @truncate(i); // safe: synthetic byte pattern deliberately cycles
        accumulator +%= callback(budget.allocator(), source[0..row.live], row.cap, row.next, row.fail);
    }
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(accumulator);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(rounds));
}
fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    return values[values.len / 2];
}
fn report(out: *std.Io.Writer, name: []const u8, measurements: []const Sample) !void {
    var base: [samples]f64 = undefined;
    var wrap: [samples]f64 = undefined;
    var ratios: [samples]f64 = undefined;
    for (measurements, 0..) |row, i| {
        base[i] = row.baseline;
        wrap[i] = row.wrapper;
        ratios[i] = row.wrapper / row.baseline;
    }
    const b = median(&base);
    const w = median(&wrap);
    var prng = std.Random.DefaultPrng.init(0xa4615);
    const random = prng.random();
    var boot: [10_000]f64 = undefined;
    for (&boot) |*value| {
        var draw: [samples]f64 = undefined;
        for (&draw) |*r| r.* = ratios[random.uintLessThan(usize, samples)];
        value.* = median(&draw);
    }
    std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
    try out.print("{s}: baseline/wrapper median={d:.3}/{d:.3} ns/op best={d:.3}/{d:.3} p95={d:.3}/{d:.3} p99={d:.3}/{d:.3} spread=[{d:.3},{d:.3}]/[{d:.3},{d:.3}] paired-ratio95=[{d:.8},{d:.8}]\n", .{ name, b, w, base[0], wrap[0], base[samples * 95 / 100], wrap[samples * 95 / 100], base[samples - 1], wrap[samples - 1], base[0], base[samples - 1], wrap[0], wrap[samples - 1], boot[250], boot[9749] });
    for (measurements) |row| try out.print("pair {s} {d:.6} {d:.6}\n", .{ name, row.baseline, row.wrapper });
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    inline for (rows) |row| {
        const base = work(row.operation, false);
        const wrap = work(row.operation, true);
        if (smoke) {
            _ = measure(init.io, base, row, 2);
            _ = measure(init.io, wrap, row, 2);
        } else {
            _ = measure(init.io, base, row, iterations / 4);
            _ = measure(init.io, wrap, row, iterations / 4);
            var measurements: [samples]Sample = undefined;
            var orders: [samples]bool = undefined;
            for (&orders, 0..) |*order, i| order.* = i < samples / 2;
            var order_prng = std.Random.DefaultPrng.init(std.hash.Wyhash.hash(0xa4615, row.name));
            order_prng.random().shuffle(bool, &orders);
            for (&measurements, orders) |*pair, base_first| {
                // Exactly balanced, reproducible randomized ABBA/BAAB avoids
                // synchronizing labels with periodic host activity. Keep all pairs.
                if (base_first) {
                    const b1 = measure(init.io, base, row, iterations);
                    const w1 = measure(init.io, wrap, row, iterations);
                    const w2 = measure(init.io, wrap, row, iterations);
                    const b2 = measure(init.io, base, row, iterations);
                    pair.* = .{ .baseline = (b1 + b2) / 2, .wrapper = (w1 + w2) / 2 };
                } else {
                    const w1 = measure(init.io, wrap, row, iterations);
                    const b1 = measure(init.io, base, row, iterations);
                    const b2 = measure(init.io, base, row, iterations);
                    const w2 = measure(init.io, wrap, row, iterations);
                    pair.* = .{ .baseline = (b1 + b2) / 2, .wrapper = (w1 + w2) / 2 };
                }
            }
            try output.interface.print("{s}: compiled callbacks shared={any}\n", .{ row.name, base == wrap });
            try report(&output.interface, row.name, &measurements);
        }
    }
    try output.interface.flush();
}
