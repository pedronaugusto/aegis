//! Extracted acquire/release spin semantics from cloak's bounded service sections.
const std = @import("std");

/// Couples data to one spin lock. After publication the owner address must remain stable.
/// Infallible/noncancelable, with no fairness bound. Sections must be bounded: no blocking,
/// yielding, recursion or arbitrary callbacks. All users must end before teardown.
/// Zig fields remain accessible: guards and borrows are caller contracts, not sealed access.
pub fn Guarded(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Marks the owner as safe to share through a mutable pointer: all access is behind its lock.
        pub const interior_lock = true;
        /// Spins taken before the yielding wait first parks through Io.
        const spins = 64;
        /// Private: never acquire or release directly.
        lock: std.atomic.Value(bool) = .init(false),
        /// Private: use a live guard; never copy/move a published owner.
        data: T,
        pub const AcquireError = std.Io.Cancelable;

        /// Initialize before publishing; the consumer owns data cleanup and reclamation.
        pub fn init(value: T) Self {
            return .{ .data = value };
        }

        /// Acquire exclusive access. Pair immediately with defer guard.deinit().
        /// One acquire swap when free; contended waiters spin on a plain load, so the lock
        /// line is not rewritten while it is held.
        pub fn acquire(owner: *Self) Guard {
            while (owner.lock.swap(true, .acquire)) {
                while (owner.lock.load(.monotonic)) std.atomic.spinLoopHint();
            }
            return .{ .owner = owner };
        }

        /// Exclusive access if the lock is free right now, otherwise null. Never waits.
        pub fn tryAcquire(owner: *Self) ?Guard {
            if (owner.lock.swap(true, .acquire)) return null;
            return .{ .owner = owner };
        }

        /// Acquire for a lock that may stay held while its holder is not running, such as on a
        /// cooperative Io: after a short spin each wait sleeps through `io`, so the holder can
        /// run. Cancellation grants no guard. The critical section itself stays bounded.
        pub fn acquireYielding(owner: *Self, io: std.Io) AcquireError!Guard {
            var tries: usize = 0;
            while (owner.lock.swap(true, .acquire)) {
                while (owner.lock.load(.monotonic)) {
                    tries += 1;
                    if (tries <= spins) {
                        std.atomic.spinLoopHint();
                    } else {
                        try io.sleep(.fromMicroseconds(50), .awake);
                    }
                }
            }
            return .{ .owner = owner };
        }

        /// The data of an owner that no other task can reach: for the sole owner's teardown, where
        /// acquiring would be needless. Asserts the lock is free in Debug and ReleaseSafe. The owner
        /// is not used again; this ends every borrow and takes no lock.
        pub fn teardown(owner: *Self) *T {
            std.debug.assert(!owner.lock.load(.monotonic));
            return &owner.data;
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
