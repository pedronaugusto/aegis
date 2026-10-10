const std = @import("std");
const narrow = @import("int.zig").narrow;

test "narrow gives null where cast gives Overflow, and the value where every source fits" {
    try std.testing.expectEqual(@as(?u8, 200), narrow(u8, @as(u32, 200)));
    try std.testing.expectEqual(@as(?u8, null), narrow(u8, @as(u32, 256)));
    try std.testing.expectEqual(@as(?u8, null), narrow(u8, @as(i32, -1)));
    try std.testing.expectEqual(@as(?i8, -128), narrow(i8, @as(i64, -128)));
    try std.testing.expectEqual(@as(?i8, null), narrow(i8, @as(i64, -129)));
    // A widening cannot fail; the result is still the optional.
    try std.testing.expectEqual(@as(?u64, 7), narrow(u64, @as(u32, 7)));
    try std.testing.expectEqual(@as(?usize, 9), narrow(usize, @as(u32, 9)));
    try std.testing.expectEqual(@as(?u8, 255), narrow(u8, 255));
    try std.testing.expectEqual(@as(?u8, null), narrow(u8, 256));
}

/// Generic over the source: one function narrows what `cast` types two ways.
fn narrowAny(comptime T: type, comptime Target: type, value: T) ?Target {
    return narrow(Target, value);
}

test "narrow is written once for generic code over any integer pair" {
    try std.testing.expectEqual(@as(?u16, 300), narrowAny(u64, u16, 300));
    try std.testing.expectEqual(@as(?u16, null), narrowAny(u64, u16, 70000));
    try std.testing.expectEqual(@as(?u64, 65535), narrowAny(u16, u64, 65535));
    try std.testing.expectEqual(@as(?i32, 5), narrowAny(u8, i32, 5));
}
