//! Own A5 paired audited-kernel benchmarks and secret-class timing diagnostics.
const std = @import("std");
const builtin = @import("builtin");
const cases = @import("choices");
const shake = @import("shakedown");
const samples = 16;
const iterations = 10000;
const Operation = *const fn (*[512]u8, *const [512]u8, *const [512]u8, usize, std.lang.Endian) u64;
fn OperationFor(comptime name: []const u8, comptime wrapped: bool) type {
    return struct {
        fn run(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: std.lang.Endian) align(64) u64 {
            return cases.run(name, wrapped, out, a, b, if (comptime std.mem.eql(u8, name, "dynamic")) (len << 16) | len else len, endian);
        }
    };
}
noinline fn measure(op: Operation, io: std.Io, a: *const [512]u8, b: *const [512]u8, count: usize) f64 {
    var out: [512]u8 = @splat(0);
    var sum: u64 = 0;
    const start = std.Io.Clock.awake.now(io);
    for (0..count) |_| sum +%= op(&out, a, b, 512, .big);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    std.mem.doNotOptimizeAway(sum);
    std.mem.doNotOptimizeAway(out);
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    // Owner requires CI compile-only benches: the preflight smoke launch exits
    // before any workload or clock read. Timings are manual.
    if (smoke) return;
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    const w = &out.interface;
    if (!smoke) try w.print("A5 Zig {s} LLVM {s}/{s}; baseline CPU; ns/caller, 16 paired ABBA/BAAB blocks x10000; randomized class order/values; diagnostics are not a proof; hardware-counter export is separate\n", .{ builtin.zig_version_string, @tagName(builtin.target.cpu.arch), builtin.target.cpu.model.name });
    var rng_inputs = std.Random.DefaultPrng.init(0xa51);
    const random = rng_inputs.random();
    inline for (cases.names) |name| {
        const baseline: Operation = &OperationFor(name, false).run;
        const wrapper: Operation = &OperationFor(name, true).run;
        var bs: [6][samples]f64 = undefined;
        var ws: [6][samples]f64 = undefined;
        for (0..samples) |i| {
            var order: [6]usize = .{ 0, 1, 2, 3, 4, 5 };
            random.shuffle(usize, &order);
            for (order) |class| {
                var a: [512]u8 = undefined;
                var b: [512]u8 = undefined;
                random.bytes(&a);
                b = a;
                const last = if (comptime std.mem.eql(u8, name, "equal1")) 0 else if (comptime std.mem.eql(u8, name, "equal32") or std.mem.startsWith(u8, name, "order")) 31 else if (comptime std.mem.eql(u8, name, "equal48") or std.mem.eql(u8, name, "finished")) 47 else 511;
                switch (class) {
                    0 => {},
                    1 => b[0] ^= 1,
                    2 => b[last] ^= 1,
                    3 => random.bytes(&b),
                    4 => {
                        a = @splat(0);
                        b = @splat(255);
                    },
                    5 => {
                        a = @splat(255);
                        b = @splat(0);
                    },
                    else => unreachable,
                }
                var xout: [512]u8 = @splat(0);
                var yout = xout;
                if (baseline(&xout, &a, &b, 512, .big) != wrapper(&yout, &a, &b, 512, .big) or !std.mem.eql(u8, &xout, &yout)) return error.CallerMismatch;
                if (smoke) {
                    _ = measure(baseline, init.io, &a, &b, 1);
                    _ = measure(wrapper, init.io, &a, &b, 1);
                    continue;
                }
                _ = measure(baseline, init.io, &a, &b, iterations / 10);
                _ = measure(wrapper, init.io, &a, &b, iterations / 10);
                var b1: f64 = undefined;
                var b2: f64 = undefined;
                var w1: f64 = undefined;
                var w2: f64 = undefined;
                if (i % 2 == 0) {
                    b1 = measure(baseline, init.io, &a, &b, iterations);
                    w1 = measure(wrapper, init.io, &a, &b, iterations);
                    w2 = measure(wrapper, init.io, &a, &b, iterations);
                    b2 = measure(baseline, init.io, &a, &b, iterations);
                } else {
                    w1 = measure(wrapper, init.io, &a, &b, iterations);
                    b1 = measure(baseline, init.io, &a, &b, iterations);
                    b2 = measure(baseline, init.io, &a, &b, iterations);
                    w2 = measure(wrapper, init.io, &a, &b, iterations);
                }
                bs[class][i] = (b1 + b2) / 2;
                ws[class][i] = (w1 + w2) / 2;
                try w.print("sample {s} class={d} i={d} b1={d:.4} w1={d:.4} b2={d:.4} w2={d:.4}\n", .{ name, class, i, b1, w1, b2, w2 });
            }
        }
        if (!smoke) {
            for (0..6) |class| {
                const bst = try shake.bench.statistics(init.gpa, &bs[class]);
                const wst = try shake.bench.statistics(init.gpa, &ws[class]);
                var boot: [2000]f64 = undefined;
                var rng = std.Random.DefaultPrng.init(0xa5);
                const r = rng.random();
                for (&boot) |*v| {
                    var ratios: [samples]f64 = undefined;
                    for (&ratios) |*ratio| {
                        const i = r.intRangeLessThan(usize, 0, samples);
                        ratio.* = ws[class][i] / bs[class][i];
                    }
                    std.mem.sort(f64, &ratios, {}, std.sort.asc(f64));
                    v.* = (ratios[7] + ratios[8]) / 2;
                }
                std.mem.sort(f64, &boot, {}, std.sort.asc(f64));
                try w.print("summary {s} class={d} best={d:.4}/{d:.4} median={d:.4}/{d:.4} p99={d:.4}/{d:.4} spread={d:.4}/{d:.4} ratio95={d:.5}..{d:.5} same-entry={any}\n", .{ name, class, bst.best, wst.best, bst.median, wst.median, bst.p99, wst.p99, bst.radius, wst.radius, boot[50], boot[1949], @intFromPtr(baseline) == @intFromPtr(wrapper) }); // safe: compare live code identity without printing addresses
            }
        }
    }
    try w.flush();
}
