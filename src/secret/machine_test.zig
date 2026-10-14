const std = @import("std");
const machine = @import("machine.zig");

noinline fn victim(fill: u8) void {
    var area: [2048]u8 = undefined;
    const volatile_area: *volatile [2048]u8 = &area;
    for (volatile_area) |*byte| byte.* = fill;
}

/// The longest run of bytes equal to `fill` in the `bytes` below this frame. A run, not a
/// count: the frame's own words may hold the byte by chance. Inlined into a test that calls
/// `@disableInstrumentation()`: a sanitizer's hook for each read runs on the stack below, in the
/// very bytes being read, and would erase the residue it is looking for.
inline fn residue(comptime bytes: usize, fill: u8) usize {
    const window: [*]const volatile u8 = @ptrFromInt(@frameAddress() - bytes);
    var longest: usize = 0;
    var run: usize = 0;
    for (0..bytes) |i| {
        run = if (window[i] == fill) run + 1 else 0;
        longest = @max(longest, run);
    }
    return longest;
}

test "scrubStack zeroes what a finished call left below the caller" {
    @disableInstrumentation();
    victim(0x5c);
    // The control: without the scrub the dead frame still holds the bytes.
    try std.testing.expect(residue(8192, 0x5c) >= 2048);
    victim(0x5c);
    machine.scrubStack(8192);
    try std.testing.expect(residue(8192, 0x5c) < 8);
}

test "stackReach measures how deep a call writes" {
    const reach = machine.stackReach(16384, victim, .{0x11});
    try std.testing.expect(reach >= 2048);
    try std.testing.expect(reach < 4096);
}

test "Timing turns data-independent timing on for its span and restores it" {
    const before = machine.Timing.active();
    {
        const timing = machine.Timing.begin();
        defer timing.end();
        try std.testing.expectEqual(machine.Timing.available, machine.Timing.active());
    }
    try std.testing.expectEqual(before, machine.Timing.active());
}

noinline fn secretWork(fill: u8, out: *u8) error{Never}!u8 {
    victim(fill);
    out.* = fill;
    return if (machine.Timing.available) @intFromBool(machine.Timing.active()) else fill;
}

test "scrubbed runs the call under data-independent timing and leaves nothing below" {
    @disableInstrumentation();
    var out: u8 = 0;
    const result = try machine.scrubbed(8192, secretWork, .{ 0x3c, &out });
    try std.testing.expectEqual(@as(u8, 0x3c), out);
    if (machine.Timing.available) try std.testing.expectEqual(@as(u8, 1), result);
    try std.testing.expect(residue(8192, 0x3c) < 8);
}
