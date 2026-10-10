//! The creator's record of one scope: a generation that moves on when the scope ends.
const builtin = @import("builtin");
const std = @import("std");

/// Scope checks follow Zig's runtime safety: on in Debug and ReleaseSafe, absent from ReleaseFast and ReleaseSmall.
pub const checked = builtin.mode == .debug or builtin.mode == .safe;

/// One past the last usable generation. A slot that reaches it is retired and never opens a scope again.
pub const retired: u64 = std.math.maxInt(u64);

/// A generation read and written without tearing where the target has 64-bit atomics, and as a plain
/// integer on narrower targets, which have no 64-bit atomics to give. There a check racing the end of its
/// scope can read half an update and call a live reference expired, never an expired one live.
const Generation = if (@bitSizeOf(usize) >= 64) std.atomic.Value(u64) else Plain;

/// The narrow-target generation, with the atomic one's operations.
pub const Plain = struct {
    raw: u64,
    pub fn init(value: u64) Plain {
        return .{ .raw = value };
    }
    pub fn load(self: *const Plain, _: std.builtin.AtomicOrder) u64 {
        return self.raw;
    }
    pub fn store(self: *Plain, value: u64, _: std.builtin.AtomicOrder) void {
        self.raw = value;
    }
};

/// Where a scope's generation lives. The creator's table owns the slots, never the scope's own memory,
/// so a check made after the scope ended still reads live metadata. Zero-sized outside Debug and ReleaseSafe.
pub const Slot = if (checked) struct {
    /// Private: the generation the open scope holds, and the next one once it ended.
    generation: Generation = .init(1),
    /// Private: the next free slot while this one is free.
    next: usize = std.math.maxInt(usize),
} else struct {};
