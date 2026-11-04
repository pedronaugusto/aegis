//! Paired exports: hand-written bump memory and the same operation through `Region`.
const std = @import("std");
const c = @import("region.zig");

export fn baselineRegionCreate(r: *c.Direct) ?*u64 {
    return c.create(false, r);
}
export fn wrapperRegionCreate(r: *c.Region) ?*u64 {
    return c.create(true, r);
}
export fn baselineRegionPush(r: *c.Direct, n: usize) ?[*]u32 {
    return c.push(false, r, n);
}
export fn wrapperRegionPush(r: *c.Region, n: usize) ?[*]u32 {
    return c.push(true, r, n);
}
export fn baselineRegionAppend(t: *c.DirectTail, value: u64) ?*u64 {
    return c.append(false, t, value);
}
export fn wrapperRegionAppend(t: *c.Tail, value: u64) ?*u64 {
    return c.append(true, t, value);
}
export fn baselineRegionMark(r: *c.Direct, out: *c.DirectMark) void {
    c.mark(false, r, out);
}
export fn wrapperRegionMark(r: *c.Region, out: *c.Mark) void {
    c.mark(true, r, out);
}
export fn baselineRegionRelease(r: *c.Direct, m: *const c.DirectMark) void {
    c.release(false, r, m);
}
export fn wrapperRegionRelease(r: *c.Region, m: *const c.Mark) void {
    c.release(true, r, m);
}
export fn baselineRegionScratch(r: *c.Direct, n: usize) u32 {
    return c.scratch(false, r, n);
}
export fn wrapperRegionScratch(r: *c.Region, n: usize) u32 {
    return c.scratch(true, r, n);
}
comptime {
    std.debug.assert(@sizeOf(c.Region) == @sizeOf(c.Direct));
    std.debug.assert(@alignOf(c.Region) == @alignOf(c.Direct));
    std.debug.assert(@sizeOf(c.Mark) == @sizeOf(c.DirectMark));
    std.debug.assert(@sizeOf(c.Tail) == @sizeOf(c.DirectTail));
    std.debug.assert(@offsetOf(c.Region, "top") == @offsetOf(c.Direct, "top"));
    std.debug.assert(@offsetOf(c.Region, "committed_end") == @offsetOf(c.Direct, "committed_end"));
}
