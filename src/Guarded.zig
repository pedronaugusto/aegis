//! Extracted acquire/release spin semantics from cloak's bounded service sections.
const std = @import("std");

/// Couples data to one spin lock. After publication the owner address must remain stable.
/// Infallible/noncancelable, with no fairness bound. Sections must be bounded: no blocking,
/// yielding, recursion or arbitrary callbacks. All users must end before teardown.
/// Zig fields remain accessible: guards and borrows are caller contracts, not sealed access.
pub fn Guarded(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: never acquire or release directly.
        lock: std.atomic.Value(bool) = .init(false),
        /// Private: use a live guard; never copy/move a published owner.
        data: T,

        /// Initialize before publishing; the consumer owns data cleanup and reclamation.
        pub fn init(value: T) Self {
            return .{ .data = value };
        }

        /// Acquire exclusive access. Pair immediately with defer guard.deinit().
        pub fn acquire(owner: *Self) Guard {
            while (owner.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
            return .{ .owner = owner };
        }

        /// A single borrowed capability. Never copy it; release exactly once.
        pub const Guard = struct {
            /// Private: valid only until deinit, on the same logical execution.
            owner: *Self,

            /// Borrow until release. Escaping slices/pointers need separate lifetime ownership.
            pub fn value(guard: *const Guard) *T {
                return &guard.owner.data;
            }

            /// Release with publication ordering and consume this capability.
            /// Does not destroy T or reclaim the owner; no copied-guard detection is promised.
            pub fn deinit(guard: *Guard) void {
                guard.owner.lock.store(false, .release);
            }
        };
    };
}

test {
    _ = @import("Guarded_test.zig");
}
