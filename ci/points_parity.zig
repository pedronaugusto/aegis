//! Paired exports: hand-written code, and the same with every fault point verb in it. Built
//! outside a test, each verb is its inert answer as it compiles, so the pairs emit the same
//! instructions, and the driver slot is in no object (ci/codegen.zig asserts both).
const a = @import("aegis");

const Point = enum { append_fails, short_read, slow_path, recovered };

export fn baselinePointsFault(x: u32) u32 {
    return x *% 3 +% 1;
}
export fn wrapperPointsFault(x: u32) u32 {
    if (a.points.fault(Point.append_fails)) return 0;
    return x *% 3 +% 1;
}
export fn baselinePointsShorten(n: usize) usize {
    return n / 3 +% 7;
}
export fn wrapperPointsShorten(n: usize) usize {
    return a.points.shorten(Point.short_read, n) / 3 +% 7;
}
export fn baselinePointsYield(x: u32) u32 {
    return x ^ 0x5a5a;
}
export fn wrapperPointsYield(x: u32) u32 {
    a.points.yield(Point.slow_path);
    return x ^ 0x5a5a;
}
export fn baselinePointsReached(x: u32) u32 {
    return x -% 9;
}
export fn wrapperPointsReached(x: u32) u32 {
    a.points.reached(Point.recovered);
    return x -% 9;
}
