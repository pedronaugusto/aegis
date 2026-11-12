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
        /// Marks the owner as safe to share through a mutable pointer: all access is behind its lock.
        pub const interior_lock = true;
        /// Private: base std lock with matching cancellation/wake semantics.
        aegis_lock: Io.RwLock = .init,
        /// Private: readers/writers admitted or waiting, bounded before std counters change.
        aegis_admitted: std.atomic.Value(usize) = .init(0),
        /// Private: never exceeds either std packed counter's finite ceiling.
        aegis_limit: usize = @min(65535, maximum_admission),
        /// Private: use the appropriate live guard.
        aegis_data: T,
        pub const AcquireError = Io.Cancelable || error{AdmissionLimit};
        pub const AdmissionError = error{AdmissionLimit};
        pub const InitError = error{InvalidLimit};
        pub fn init(value: T) Self {
            return .{ .aegis_data = value };
        }
        pub fn initLimit(value: T, limit: usize) InitError!Self {
            if (limit > maximum_admission) return error.InvalidLimit;
            return .{ .aegis_data = value, .aegis_limit = limit };
        }
        fn admit(self: *Self) AdmissionError!void {
            var old = self.aegis_admitted.load(.monotonic);
            while (true) {
                if (old == self.aegis_limit) return error.AdmissionLimit;
                old = self.aegis_admitted.cmpxchgWeak(old, old + 1, .monotonic, .monotonic) orelse return;
            }
        }
        fn depart(self: *Self) void {
            _ = self.aegis_admitted.fetchSub(1, .monotonic);
        }
        pub fn read(self: *Self, io: Io) AcquireError!ReadGuard {
            try self.admit();
            errdefer self.depart();
            try self.aegis_lock.lockShared(io);
            return .{ .aegis_owner = self };
        }
        pub fn write(self: *Self, io: Io) AcquireError!WriteGuard {
            try self.admit();
            errdefer self.depart();
            try self.aegis_lock.lock(io);
            return .{ .aegis_owner = self };
        }
        pub fn readUncancelable(self: *Self, io: Io) AdmissionError!ReadGuard {
            try self.admit();
            self.aegis_lock.lockSharedUncancelable(io);
            return .{ .aegis_owner = self };
        }
        pub fn writeUncancelable(self: *Self, io: Io) AdmissionError!WriteGuard {
            try self.admit();
            self.aegis_lock.lockUncancelable(io);
            return .{ .aegis_owner = self };
        }
        pub fn tryRead(self: *Self, io: Io) AdmissionError!?ReadGuard {
            try self.admit();
            if (!self.aegis_lock.tryLockShared(io)) {
                self.depart();
                return null;
            }
            return .{ .aegis_owner = self };
        }
        pub fn tryWrite(self: *Self, io: Io) AdmissionError!?WriteGuard {
            try self.admit();
            if (!self.aegis_lock.tryLock(io)) {
                self.depart();
                return null;
            }
            return .{ .aegis_owner = self };
        }
        /// The data of an owner that no other task can reach: for the sole owner's teardown, which
        /// then needs no Io. Asserts nobody is admitted in Debug and ReleaseSafe. The owner is not
        /// used again; this ends every borrow and takes no lock.
        pub fn teardown(self: *Self) *T {
            std.debug.assert(self.aegis_admitted.load(.monotonic) == 0);
            return &self.aegis_data;
        }
        pub const ReadGuard = struct {
            /// Private: uncopied logical-task capability.
            aegis_owner: *Self,
            pub fn value(self: *const ReadGuard) *const T {
                return &self.aegis_owner.aegis_data;
            }
            pub fn deinit(self: *ReadGuard, io: Io) void {
                self.aegis_owner.aegis_lock.unlockShared(io);
                self.aegis_owner.depart();
            }
        };
        pub const WriteGuard = struct {
            /// Private: uncopied logical-task capability.
            aegis_owner: *Self,
            pub fn value(self: *const WriteGuard) *T {
                return &self.aegis_owner.aegis_data;
            }
            pub fn deinit(self: *WriteGuard, io: Io) void {
                self.aegis_owner.aegis_lock.unlock(io);
                self.aegis_owner.depart();
            }
        };
    };
}
