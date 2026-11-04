//! Paired exports: a hand-written free list over slots and the same operation through `SlotPool`.
const std = @import("std");
const c = @import("pool.zig");

export fn baselinePoolAlloc(p: *c.Direct, value: u64) u32 {
    return c.alloc(false, p, value);
}
export fn wrapperPoolAlloc(p: *c.Slots, value: u64) u32 {
    return c.alloc(true, p, value);
}
export fn baselinePoolFree(p: *c.Direct, raw: u32) void {
    c.free(false, p, raw);
}
export fn wrapperPoolFree(p: *c.Slots, raw: u32) void {
    c.free(true, p, raw);
}
export fn baselinePoolGet(p: *const c.Direct, raw: u32) u64 {
    return c.get(false, p, raw);
}
export fn wrapperPoolGet(p: *const c.Slots, raw: u32) u64 {
    return c.get(true, p, raw);
}
export fn baselineRunSlice(p: *const c.Runs, start: u32, len: u32) [*]u64 {
    return c.slice(false, p, start, len);
}
export fn wrapperRunSlice(p: *const c.Runs, start: u32, len: u32) [*]u64 {
    return c.slice(true, p, start, len);
}
comptime {
    std.debug.assert(@sizeOf(c.Slots) == @sizeOf(c.Direct));
    std.debug.assert(@sizeOf(c.Slots.Slot) == @sizeOf(c.DirectSlot));
    std.debug.assert(@offsetOf(c.Slots, "slots") == @offsetOf(c.Direct, "slots"));
}
