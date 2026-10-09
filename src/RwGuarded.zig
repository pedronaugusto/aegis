//! std.Io.RwLock plus an equally necessary all-build admission ceiling.
const std = @import("std");
const Io = std.Io;
/// Read borrows do not make mutable pointees thread-safe. No upgrade/downgrade or recursion.
/// The owner remains stable and outlives all guards, blocked callers and pointee owners.
pub fn RwGuarded(comptime T: type) type {
    return struct {
        const Self = @This();
        const Count = @Int(.unsigned, @divFloor(@bitSizeOf(usize) - 1, 2));
        pub const maximum_admission = std.math.maxInt(Count);
        /// Private: base std lock with matching cancellation/wake semantics.
        lock: Io.RwLock = .init,
        /// Private: readers/writers admitted or waiting, bounded before std counters change.
        admitted: std.atomic.Value(usize) = .init(0),
        /// Private: never exceeds either std packed counter's finite ceiling.
        limit: usize = @min(65535, maximum_admission),
        /// Private: use the appropriate live guard.
        data: T,
        pub const AcquireError = Io.Cancelable || error{AdmissionLimit};
        pub const AdmissionError = error{AdmissionLimit};
        pub const InitError = error{InvalidLimit};
        pub fn init(value: T) Self {
            return .{ .data = value };
        }
        pub fn initLimit(value: T, limit: usize) InitError!Self {
            if (limit > maximum_admission) return error.InvalidLimit;
            return .{ .data = value, .limit = limit };
        }
        fn admit(self: *Self) AdmissionError!void {
            var old = self.admitted.load(.monotonic);
            while (true) {
                if (old == self.limit) return error.AdmissionLimit;
                old = self.admitted.cmpxchgWeak(old, old + 1, .monotonic, .monotonic) orelse return;
            }
        }
        fn depart(self: *Self) void {
            _ = self.admitted.fetchSub(1, .monotonic);
        }
        pub fn read(self: *Self, io: Io) AcquireError!ReadGuard {
            try self.admit();
            errdefer self.depart();
            try self.lock.lockShared(io);
            return .{ .owner = self };
        }
        pub fn write(self: *Self, io: Io) AcquireError!WriteGuard {
            try self.admit();
            errdefer self.depart();
            try self.lock.lock(io);
            return .{ .owner = self };
        }
        pub fn readUncancelable(self: *Self, io: Io) AdmissionError!ReadGuard {
            try self.admit();
            self.lock.lockSharedUncancelable(io);
            return .{ .owner = self };
        }
        pub fn writeUncancelable(self: *Self, io: Io) AdmissionError!WriteGuard {
            try self.admit();
            self.lock.lockUncancelable(io);
            return .{ .owner = self };
        }
        pub fn tryRead(self: *Self, io: Io) AdmissionError!?ReadGuard {
            try self.admit();
            if (!self.lock.tryLockShared(io)) {
                self.depart();
                return null;
            }
            return .{ .owner = self };
        }
        pub fn tryWrite(self: *Self, io: Io) AdmissionError!?WriteGuard {
            try self.admit();
            if (!self.lock.tryLock(io)) {
                self.depart();
                return null;
            }
            return .{ .owner = self };
        }
        pub const ReadGuard = struct {
            /// Private: uncopied logical-task capability.
            owner: *Self,
            pub fn value(self: *const ReadGuard) *const T {
                return &self.owner.data;
            }
            pub fn deinit(self: *ReadGuard, io: Io) void {
                self.owner.lock.unlockShared(io);
                self.owner.depart();
            }
        };
        pub const WriteGuard = struct {
            /// Private: uncopied logical-task capability.
            owner: *Self,
            pub fn value(self: *const WriteGuard) *T {
                return &self.owner.data;
            }
            pub fn deinit(self: *WriteGuard, io: Io) void {
                self.owner.lock.unlock(io);
                self.owner.depart();
            }
        };
    };
}
