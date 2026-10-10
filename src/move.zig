//! The one move rule of the library: a payload that declares `moveInto` moves through it, any other is copied.
//! Base layer: the owners, containers, pools and stages above all move through this file and no other.
const std = @import("std");
const builtin = @import("builtin");

/// Whether `T` declares its own move.
inline fn declared(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "moveInto"),
        else => false,
    };
}

/// Moves `source` into `destination` through `moveInto` when `T` declares it, else by assignment. A copied
/// source is left as it was; a payload with `moveInto` leaves its source as that move says.
pub inline fn into(comptime T: type, source: *T, destination: *T) void {
    if (comptime declared(T)) {
        source.moveInto(destination);
    } else {
        destination.* = source.*;
    }
}

/// The handle pools' variant: as `into`, and a source that was copied is then set to `undefined`, so a
/// payload read after it was handed over shows as garbage in Debug and ReleaseSafe. A payload with
/// `moveInto` is left to its own move.
pub inline fn intoPoisoning(comptime T: type, source: *T, destination: *T) void {
    if (comptime declared(T)) {
        source.moveInto(destination);
    } else {
        destination.* = source.*;
        source.* = undefined;
    }
}

const Counted = struct {
    value: u32,
    moves: u32 = 0,
    pub fn moveInto(self: *Counted, destination: *Counted) void {
        destination.* = .{ .value = self.value, .moves = self.moves + 1 };
        self.value = 0;
    }
};

test "move: a declared moveInto decides what the source keeps, in both forms" {
    var source: Counted = .{ .value = 7 };
    var destination: Counted = undefined;
    into(Counted, &source, &destination);
    try std.testing.expectEqual(@as(u32, 7), destination.value);
    try std.testing.expectEqual(@as(u32, 1), destination.moves);
    try std.testing.expectEqual(@as(u32, 0), source.value);

    var again: Counted = .{ .value = 9 };
    intoPoisoning(Counted, &again, &destination);
    try std.testing.expectEqual(@as(u32, 9), destination.value);
    try std.testing.expectEqual(@as(u32, 0), again.value);
}

test "move: a type without moveInto is copied and only the poisoning form clears the source" {
    var source: [3]u16 = .{ 1, 2, 3 };
    var destination: [3]u16 = undefined;
    into([3]u16, &source, &destination);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, &destination);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, &source);

    var other: [3]u16 = .{ 4, 5, 6 };
    intoPoisoning([3]u16, &other, &destination);
    try std.testing.expectEqualSlices(u16, &.{ 4, 5, 6 }, &destination);
    if (builtin.mode == .debug) {
        // Debug fills `undefined` with 0xaa bytes.
        for (other) |word| try std.testing.expectEqual(@as(u16, 0xaaaa), word);
    }
}
