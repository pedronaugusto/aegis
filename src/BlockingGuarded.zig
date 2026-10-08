//! std.Io.Mutex semantics with guard-owned access, no stored Io.
const std = @import("std");
/// Stable after publication. Join/drain users before moving or destroying the owner.
pub fn BlockingGuarded(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: synchronization kernel; no unlocked data access.
        mutex: std.Io.Mutex = .init,
        /// Private: only borrow through a live guard.
        data: T,
        pub const AcquireError = std.Io.Cancelable;
        pub fn init(value: T) Self {
            return .{ .data = value };
        }
        /// Immediate success uses std's cancellation-point semantics.
        pub fn acquire(self: *Self, io: std.Io) AcquireError!Guard {
            try self.mutex.lock(io);
            return .{ .owner = self };
        }
        pub fn acquireUncancelable(self: *Self, io: std.Io) Guard {
            self.mutex.lockUncancelable(io);
            return .{ .owner = self };
        }
        pub fn tryAcquire(self: *Self) ?Guard {
            if (!self.mutex.tryLock()) return null;
            return .{ .owner = self };
        }
        /// Uncopied single-task capability. All borrows end before wait or release.
        pub const Guard = struct {
            /// Private: stable owner, valid until explicit release.
            owner: *Self,
            pub fn value(self: *const Guard) *T {
                return &self.owner.data;
            }
            /// Exactly once, using the same Io execution domain. Does not clean T.
            pub inline fn deinit(self: *Guard, io: std.Io) void {
                self.owner.mutex.unlock(io);
            }
        };
    };
}
