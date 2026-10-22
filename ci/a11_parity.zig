//! Paired exports for the modules A11 brought under the gate; check-parity compares them.
const std = @import("std");
const a = @import("aegis");
const c = @import("a11.zig");
comptime {
    std.debug.assert(@sizeOf(a.SpinRwGuarded(u64)) == @sizeOf(c.DirectSpinRw));
    std.debug.assert(@alignOf(a.SpinRwGuarded(u64)) == @alignOf(c.DirectSpinRw));
    std.debug.assert(@sizeOf(a.SpinRwGuarded(u64).ReadGuard) == @sizeOf(*c.DirectSpinRw));
    std.debug.assert(@sizeOf(a.SpinRwGuarded(u64).WriteGuard) == @sizeOf(*c.DirectSpinRw));
}
export fn baselineA11SpinRwRead(owner: *c.DirectSpinRw) u64 {
    return c.spinRead(false, owner);
}
export fn wrapperA11SpinRwRead(owner: *a.SpinRwGuarded(u64)) u64 {
    return c.spinRead(true, owner);
}
export fn baselineA11SpinRwWrite(owner: *c.DirectSpinRw, value: u64) void {
    c.spinWrite(false, owner, value);
}
export fn wrapperA11SpinRwWrite(owner: *a.SpinRwGuarded(u64), value: u64) void {
    c.spinWrite(true, owner, value);
}
export fn baselineA11TimingSpan(value: *const [32]u8) u8 {
    return c.timingSpan(false, value);
}
export fn wrapperA11TimingSpan(value: *const [32]u8) u8 {
    return c.timingSpan(true, value);
}
export fn baselineA11ScrubStack() void {
    c.scrub(false);
}
export fn wrapperA11ScrubStack() void {
    c.scrub(true);
}
