//! Single-owner containers and externally synchronized admission. No hidden growth.
const std = @import("std");
const builtin = @import("builtin");
const diagnostics = builtin.mode == .debug;

fn transfer(comptime T: type, source: *T, destination: *T) void {
    const has_move = switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum" => @hasDecl(T, "moveInto"),
        else => false,
    };
    if (has_move) source.moveInto(destination) else destination.* = source.*;
}

/// Initialized prefix; success transfers input, failure preserves it.
pub fn Array(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        /// Private: only the prefix is initialized.
        storage: [N]T = undefined,
        /// Private: use len/items.
        used: usize = 0,
        pub const init: Self = .{};
        pub const AppendError = error{Full};
        pub const AtError = error{OutOfBounds};
        pub const PopError = error{Empty};
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        pub fn items(self: *Self) []T {
            return self.storage[0..self.used];
        }
        pub fn append(self: *Self, value: *T) AppendError!void {
            if (N == 0) return error.Full;
            if (self.used == N) return error.Full;
            transfer(T, value, &self.storage[self.used]);
            self.used += 1;
        }
        pub fn at(self: *Self, index: usize) AtError!*T {
            if (N == 0) return error.OutOfBounds;
            if (index >= self.used) return error.OutOfBounds;
            return &self.storage[index];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            if (N == 0) return error.Empty;
            if (self.used == 0) return error.Empty;
            self.used -= 1;
            transfer(T, &self.storage[self.used], destination);
        }
        /// Cleanup must be infallible/nonblocking. Invalidates every borrow.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.items()) |*value| cleanup(value);
            self.used = 0;
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
        }
    };
}

/// FIFO with arbitrary nonzero capacity. Full never silently overwrites.
pub fn Ring(comptime T: type, comptime N: usize) type {
    if (N == 0) @compileError("ring capacity must be nonzero");
    return struct {
        const Self = @This();
        /// Private: only live cursor entries are initialized.
        storage: [N]T = undefined,
        /// Private: cursor arithmetic never adds two potentially overflowing indices.
        head: usize = 0,
        /// Private: bounded live count.
        used: usize = 0,
        pub const init: Self = .{};
        pub const PushError = error{Full};
        pub const PopError = error{Empty};
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        fn index(self: *const Self, offset: usize) usize {
            const remaining = N - self.head;
            return if (offset < remaining) self.head + offset else offset - remaining;
        }
        pub fn push(self: *Self, value: *T) PushError!void {
            if (self.used == N) return error.Full;
            transfer(T, value, &self.storage[self.index(self.used)]);
            self.used += 1;
        }
        pub fn peek(self: *Self) PopError!*T {
            if (self.used == 0) return error.Empty;
            return &self.storage[self.head];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            transfer(T, try self.peek(), destination);
            self.head = if (self.head == N - 1) 0 else self.head + 1;
            self.used -= 1;
        }
        /// On full, transfers the displaced owner to evicted. On nonfull, evicted stays uninitialized.
        /// Returns whether eviction occurred. Input/destination must be disjoint from live storage.
        pub fn overwrite(self: *Self, value: *T, evicted: *T) bool {
            const full = self.used == N;
            // unreachable: a full nonzero ring has a live head.
            if (full) self.pop(evicted) catch unreachable;
            // unreachable: eviction or nonfull admission leaves one free slot.
            self.push(value) catch unreachable;
            return full;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.used != 0) {
                var value: T = undefined;
                // unreachable: loop condition proves a live head.
                self.pop(&value) catch unreachable;
                cleanup(&value);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
        }
    };
}
/// FIFO spelling of the same bounded ring policy; no concurrent/MPMC promise.
pub const Queue = Ring;

/// Explicit caller-backed or allocated prefix with an immutable finite growth ceiling.
/// Allocated storage retains gpa; caller-backed reserve refuses growth.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: backing extent, initialized only through used.
        storage: []T,
        /// Private: nonnull only for allocated ownership.
        gpa: ?std.mem.Allocator,
        /// Private: finite growth ceiling.
        maximum: usize,
        /// Private: live prefix.
        used: usize = 0,
        pub const InitError = std.mem.Allocator.Error || error{CapacityExceeded};
        pub const ReserveError = InitError || error{CallerBacked};
        pub const AppendError = error{Full};
        pub const PopError = error{Empty};
        pub const AtError = error{OutOfBounds};
        pub fn initBuffer(storage: []T) Self {
            return .{ .storage = storage, .gpa = null, .maximum = storage.len };
        }
        pub fn initAllocated(gpa: std.mem.Allocator, capacity: usize, maximum: usize) InitError!Self {
            if (capacity > maximum or maximum > std.math.maxInt(usize) / @max(1, @sizeOf(T))) return error.CapacityExceeded;
            return .{ .storage = try gpa.alloc(T, capacity), .gpa = gpa, .maximum = maximum };
        }
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        pub fn items(self: *Self) []T {
            return self.storage[0..self.used];
        }
        pub fn at(self: *Self, index: usize) AtError!*T {
            if (index >= self.used) return error.OutOfBounds;
            return &self.storage[index];
        }
        pub fn append(self: *Self, value: *T) AppendError!void {
            if (self.used == self.storage.len) return error.Full;
            transfer(T, value, &self.storage[self.used]);
            self.used += 1;
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            if (self.used == 0) return error.Empty;
            self.used -= 1;
            transfer(T, &self.storage[self.used], destination);
        }
        /// OOM leaves all owners and borrows intact; success moves the prefix without cleanup/copy ownership.
        pub fn reserve(self: *Self, capacity: usize) ReserveError!void {
            if (capacity > self.maximum) return error.CapacityExceeded;
            if (capacity <= self.storage.len) return;
            const gpa = self.gpa orelse return error.CallerBacked;
            const storage = try gpa.alloc(T, capacity);
            for (self.items(), storage[0..self.used]) |*source, *destination| transfer(T, source, destination);
            gpa.free(self.storage);
            self.storage = storage;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.items()) |*value| cleanup(value);
            self.used = 0;
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            if (self.gpa) |gpa| gpa.free(self.storage);
            self.* = undefined;
        }
    };
}

/// Dynamic FIFO with the same explicit capacity, growth and ownership policy as Buffer.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: backing storage owned only when gpa is nonnull.
        storage: []T,
        gpa: ?std.mem.Allocator,
        maximum: usize,
        head: usize = 0,
        used: usize = 0,
        pub const InitError = std.mem.Allocator.Error || error{InvalidCapacity};
        pub const ReserveError = InitError || error{ CapacityExceeded, CallerBacked };
        pub const PushError = error{Full};
        pub const PopError = error{Empty};
        pub fn initBuffer(storage: []T) InitError!Self {
            if (storage.len == 0) return error.InvalidCapacity;
            return .{ .storage = storage, .gpa = null, .maximum = storage.len };
        }
        pub fn initAllocated(gpa: std.mem.Allocator, capacity: usize, maximum: usize) InitError!Self {
            if (capacity == 0 or capacity > maximum or maximum > std.math.maxInt(usize) / @max(1, @sizeOf(T))) return error.InvalidCapacity;
            return .{ .storage = try gpa.alloc(T, capacity), .gpa = gpa, .maximum = maximum };
        }
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        fn index(self: *const Self, offset: usize) usize {
            const remaining = self.storage.len - self.head;
            return if (offset < remaining) self.head + offset else offset - remaining;
        }
        pub fn push(self: *Self, value: *T) PushError!void {
            if (self.used == self.storage.len) return error.Full;
            transfer(T, value, &self.storage[self.index(self.used)]);
            self.used += 1;
        }
        pub fn peek(self: *Self) PopError!*T {
            if (self.used == 0) return error.Empty;
            return &self.storage[self.head];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            transfer(T, try self.peek(), destination);
            self.head = if (self.head == self.storage.len - 1) 0 else self.head + 1;
            self.used -= 1;
        }
        pub fn overwrite(self: *Self, value: *T, evicted: *T) bool {
            const full = self.used == self.storage.len;
            // unreachable: a full nonzero ring has a live head.
            if (full) self.pop(evicted) catch unreachable;
            // unreachable: eviction or nonfull admission leaves a free slot.
            self.push(value) catch unreachable;
            return full;
        }
        /// OOM preserves owners, cursors and borrows. Successful reserve linearizes FIFO storage.
        pub fn reserve(self: *Self, capacity: usize) ReserveError!void {
            if (capacity > self.maximum) return error.CapacityExceeded;
            if (capacity <= self.storage.len) return;
            const gpa = self.gpa orelse return error.CallerBacked;
            const storage = try gpa.alloc(T, capacity);
            for (0..self.used) |i| transfer(T, &self.storage[self.index(i)], &storage[i]);
            gpa.free(self.storage);
            self.storage = storage;
            self.head = 0;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.used != 0) {
                var value: T = undefined;
                // unreachable: loop condition proves a live head.
                self.pop(&value) catch unreachable;
                cleanup(&value);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            if (self.gpa) |gpa| gpa.free(self.storage);
            self.* = undefined;
        }
    };
}
/// Dynamic FIFO spelling of the bounded ring policy.
pub const QueueBuffer = RingBuffer;

fn unsigned(comptime Repr: type) void {
    switch (@typeInfo(Repr)) {
        .int => |info| if (info.signedness != .unsigned or info.bits == 0) @compileError("limit repr must be an unsigned integer"),
        else => @compileError("limit repr must be an unsigned integer"),
    }
}
/// Zero is a finite zero limit, never a sentinel for unlimited.
pub fn Limit(comptime Repr: type) type {
    unsigned(Repr);
    return struct {
        const Self = @This();
        /// Private: configured finite maximum.
        maximum: Repr,
        pub const CheckError = error{LimitExceeded};
        pub fn init(maximum: Repr) Self {
            return .{ .maximum = maximum };
        }
        /// Whether `amount` is over the maximum; an amount equal to it is within.
        pub fn exceeds(self: Self, amount: Repr) bool {
            return amount > self.maximum;
        }
        pub fn check(self: Self, amount: Repr) CheckError!void {
            if (self.exceeds(amount)) return error.LimitExceeded;
        }
    };
}

/// Externally guarded count/work budget. Must outlive every uncopied reservation.
pub fn Budget(comptime Repr: type) type {
    unsigned(Repr);
    return struct {
        const Self = @This();
        /// Private: finite ceiling.
        maximum: Repr,
        /// Private: outstanding reservations plus permanently consumed work.
        used: Repr = 0,
        pub const ReserveError = error{LimitExceeded};
        pub fn init(maximum: Repr) Self {
            return .{ .maximum = maximum };
        }
        fn charge(self: *Self, amount: Repr) ReserveError!void {
            if (amount > self.maximum - self.used) return error.LimitExceeded;
            self.used += amount;
        }
        pub fn reserve(self: *Self, amount: Repr) ReserveError!Reservation {
            try self.charge(amount);
            return .{ .budget = self, .amount = amount };
        }
        pub fn consume(self: *Self, amount: Repr) ReserveError!void {
            try self.charge(amount);
        }
        pub fn remaining(self: *const Self) Repr {
            return self.maximum - self.used;
        }
        pub const Reservation = struct {
            /// Private: stable borrowed budget.
            budget: *Self,
            /// Private: charged amount.
            amount: Repr,
            /// Private: Debug-only exactly-once witness; copies remain caller violations.
            live: if (diagnostics) bool else void = if (diagnostics) true else {},
            pub fn release(self: *Reservation) void {
                if (diagnostics) {
                    std.debug.assert(self.live);
                    self.live = false;
                }
                if (self.amount > self.budget.used) @panic("budget reservation underflow");
                self.budget.used -= self.amount;
            }
            pub fn moveInto(self: *Reservation, destination: *Reservation) void {
                if (diagnostics) {
                    std.debug.assert(self.live);
                    std.debug.assert(self != destination);
                }
                destination.* = .{ .budget = self.budget, .amount = self.amount };
                if (diagnostics) self.live = false;
            }
        };
    };
}
