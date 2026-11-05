//! A saturating aligned measure: sizes added, multiplied and aligned stop at a ceiling that no real
//! size reaches, so a measure never overflows and every excess is the one value `ceiling`, which
//! stays the ceiling through every later step. `flat` measures under 4 GiB, where its offsets
//! end; `parts` under the address space.
const std = @import("std");

pub fn Measure(comptime T: type, comptime ceiling: T) type {
    return struct {
        pub const limit = ceiling;

        pub fn add(a: T, b: T) T {
            return @min(a +| b, ceiling);
        }
        pub fn times(n: T, stride: T) T {
            return @min(n *| stride, ceiling);
        }
        /// `at` rounded up to `align_to`, a power of two; the ceiling when that passes it.
        pub fn aligned(at: T, align_to: T) T {
            if (at > ceiling - (align_to - 1)) return ceiling;
            return std.mem.alignForward(T, at, align_to);
        }
    };
}

test "a measure saturates at its ceiling and stays there" {
    const M = Measure(u64, 1 << 32);
    try std.testing.expectEqual(@as(u64, 1 << 32), M.add((1 << 32) - 1, 2));
    try std.testing.expectEqual(@as(u64, 1 << 32), M.times(1 << 20, 1 << 13));
    try std.testing.expectEqual(@as(u64, 1 << 32), M.aligned((1 << 32) - 3, 16));
    try std.testing.expectEqual(@as(u64, 48), M.aligned(33, 16));
    const U = Measure(usize, std.math.maxInt(usize));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(usize)), U.aligned(std.math.maxInt(usize) - 2, 8));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(usize)), U.add(U.aligned(std.math.maxInt(usize), 64), 0));
}
