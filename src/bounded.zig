//! Single-owner containers and externally synchronized admission. No hidden growth.
const std = @import("std");
const builtin = @import("builtin");
const move = @import("move.zig");
const diagnostics = builtin.optimize == .debug;

/// Initialized prefix; success transfers input, failure preserves it.
pub fn Array(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        /// Private: only the prefix is initialized.
        aegis_storage: [N]T = undefined,
        /// Private: use len/items.
        aegis_used: usize = 0,
        pub const init: Self = .{};
        pub const AppendError = error{Full};
        pub const AtError = error{OutOfBounds};
        pub const PopError = error{Empty};
        pub fn len(self: *const Self) usize {
            return self.aegis_used;
        }
        /// How many it holds as it stands; a full one fails its next append with `Full`.
        pub fn capacity(_: *const Self) usize {
            return N;
        }
        /// Whether the next append or push would fail with `Full`.
        pub fn isFull(self: *const Self) bool {
            return self.aegis_used == N;
        }
        pub fn items(self: *Self) []T {
            return self.aegis_storage[0..self.aegis_used];
        }
        /// The initialized prefix, read-only: what a `const` array or a by-value copy of one shows.
        pub fn constItems(self: *const Self) []const T {
            return self.aegis_storage[0..self.aegis_used];
        }
        /// Copies `values` after the prefix, or none of them: `Full` leaves the array as it was. Only for
        /// a payload that is copied, not one that declares `moveInto`, which `append` moves one at a time.
        pub fn appendSlice(self: *Self, values: []const T) AppendError!void {
            comptime std.debug.assert(!move.declares(T));
            if (values.len > N - self.aegis_used) return error.Full;
            @memcpy(self.aegis_storage[self.aegis_used..][0..values.len], values);
            self.aegis_used += values.len;
        }
        /// An array holding a copy of `values`; `Full` when they are more than `N`. As `appendSlice`.
        pub fn fromSlice(values: []const T) AppendError!Self {
            var array: Self = .init;
            try array.appendSlice(values);
            return array;
        }
        pub fn append(self: *Self, value: *T) AppendError!void {
            if (N == 0) return error.Full;
            if (self.aegis_used == N) return error.Full;
            move.into(T, value, &self.aegis_storage[self.aegis_used]);
            self.aegis_used += 1;
        }
        pub fn at(self: *Self, index: usize) AtError!*T {
            if (N == 0) return error.OutOfBounds;
            if (index >= self.aegis_used) return error.OutOfBounds;
            return &self.aegis_storage[index];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            if (N == 0) return error.Empty;
            if (self.aegis_used == 0) return error.Empty;
            self.aegis_used -= 1;
            move.into(T, &self.aegis_storage[self.aegis_used], destination);
        }
        /// Cleanup must be infallible/nonblocking. Invalidates every borrow.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.items()) |*value| cleanup(value);
            self.aegis_used = 0;
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
        aegis_storage: [N]T = undefined,
        /// Private: cursor arithmetic never adds two potentially overflowing indices.
        aegis_head: usize = 0,
        /// Private: bounded live count.
        aegis_used: usize = 0,
        pub const init: Self = .{};
        pub const PushError = error{Full};
        pub const PopError = error{Empty};
        pub fn len(self: *const Self) usize {
            return self.aegis_used;
        }
        /// How many it holds as it stands; a full one fails its next append with `Full`.
        pub fn capacity(_: *const Self) usize {
            return N;
        }
        /// Whether the next append or push would fail with `Full`.
        pub fn isFull(self: *const Self) bool {
            return self.aegis_used == N;
        }
        fn index(self: *const Self, offset: usize) usize {
            const remaining = N - self.aegis_head;
            return if (offset < remaining) self.aegis_head + offset else offset - remaining;
        }
        pub fn push(self: *Self, value: *T) PushError!void {
            if (self.aegis_used == N) return error.Full;
            move.into(T, value, &self.aegis_storage[self.index(self.aegis_used)]);
            self.aegis_used += 1;
        }
        pub fn peek(self: *Self) PopError!*T {
            if (self.aegis_used == 0) return error.Empty;
            return &self.aegis_storage[self.aegis_head];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            move.into(T, try self.peek(), destination);
            self.aegis_head = if (self.aegis_head == N - 1) 0 else self.aegis_head + 1;
            self.aegis_used -= 1;
        }
        /// On full, transfers the displaced owner to evicted. On nonfull, evicted stays uninitialized.
        /// Returns whether eviction occurred. Input/destination must be disjoint from live storage.
        pub fn overwrite(self: *Self, value: *T, evicted: *T) bool {
            const full = self.aegis_used == N;
            // unreachable: a full nonzero ring has a live head.
            if (full) self.pop(evicted) catch unreachable;
            // unreachable: eviction or nonfull admission leaves one free slot.
            self.push(value) catch unreachable;
            return full;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.aegis_used != 0) {
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
/// Explicit caller-backed or allocated prefix with an immutable finite growth ceiling.
/// Allocated storage retains gpa; caller-backed reserve refuses growth.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: backing extent, initialized only through used.
        aegis_storage: []T,
        /// Private: nonnull only for allocated ownership.
        aegis_gpa: ?std.mem.Allocator,
        /// Private: finite growth ceiling.
        aegis_maximum: usize,
        /// Private: live prefix.
        aegis_used: usize = 0,
        pub const InitError = std.mem.Allocator.Error || error{CapacityExceeded};
        pub const ReserveError = InitError || error{CallerBacked};
        pub const AppendError = error{Full};
        pub const PopError = error{Empty};
        pub const AtError = error{OutOfBounds};
        pub fn initBuffer(storage: []T) Self {
            return .{ .aegis_storage = storage, .aegis_gpa = null, .aegis_maximum = storage.len };
        }
        pub fn initAllocated(gpa: std.mem.Allocator, initial: usize, maximum: usize) InitError!Self {
            if (initial > maximum or maximum > std.math.maxInt(usize) / @max(1, @sizeOf(T))) return error.CapacityExceeded;
            return .{ .aegis_storage = try gpa.alloc(T, initial), .aegis_gpa = gpa, .aegis_maximum = maximum };
        }
        pub fn len(self: *const Self) usize {
            return self.aegis_used;
        }
        /// How many it holds as it stands; a full one fails its next append with `Full`.
        pub fn capacity(self: *const Self) usize {
            return self.aegis_storage.len;
        }
        /// Whether the next append or push would fail with `Full`.
        pub fn isFull(self: *const Self) bool {
            return self.aegis_used == self.aegis_storage.len;
        }
        pub fn items(self: *Self) []T {
            return self.aegis_storage[0..self.aegis_used];
        }
        pub fn at(self: *Self, index: usize) AtError!*T {
            if (index >= self.aegis_used) return error.OutOfBounds;
            return &self.aegis_storage[index];
        }
        pub fn append(self: *Self, value: *T) AppendError!void {
            if (self.aegis_used == self.aegis_storage.len) return error.Full;
            move.into(T, value, &self.aegis_storage[self.aegis_used]);
            self.aegis_used += 1;
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            if (self.aegis_used == 0) return error.Empty;
            self.aegis_used -= 1;
            move.into(T, &self.aegis_storage[self.aegis_used], destination);
        }
        /// OOM leaves all owners and borrows intact; success moves the prefix without cleanup/copy ownership.
        pub fn reserve(self: *Self, wanted: usize) ReserveError!void {
            if (wanted > self.aegis_maximum) return error.CapacityExceeded;
            if (wanted <= self.aegis_storage.len) return;
            const gpa = self.aegis_gpa orelse return error.CallerBacked;
            const storage = try gpa.alloc(T, wanted);
            for (self.items(), storage[0..self.aegis_used]) |*source, *destination| move.into(T, source, destination);
            gpa.free(self.aegis_storage);
            self.aegis_storage = storage;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.items()) |*value| cleanup(value);
            self.aegis_used = 0;
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            if (self.aegis_gpa) |gpa| gpa.free(self.aegis_storage);
            self.* = undefined;
        }
    };
}

/// Dynamic FIFO with the same explicit capacity, growth and ownership policy as Buffer.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: backing storage owned only when gpa is nonnull.
        aegis_storage: []T,
        aegis_gpa: ?std.mem.Allocator,
        aegis_maximum: usize,
        aegis_head: usize = 0,
        aegis_used: usize = 0,
        pub const InitError = std.mem.Allocator.Error || error{InvalidCapacity};
        pub const ReserveError = InitError || error{ CapacityExceeded, CallerBacked };
        pub const PushError = error{Full};
        pub const PopError = error{Empty};
        pub fn initBuffer(storage: []T) InitError!Self {
            if (storage.len == 0) return error.InvalidCapacity;
            return .{ .aegis_storage = storage, .aegis_gpa = null, .aegis_maximum = storage.len };
        }
        pub fn initAllocated(gpa: std.mem.Allocator, initial: usize, maximum: usize) InitError!Self {
            if (initial == 0 or initial > maximum or maximum > std.math.maxInt(usize) / @max(1, @sizeOf(T))) return error.InvalidCapacity;
            return .{ .aegis_storage = try gpa.alloc(T, initial), .aegis_gpa = gpa, .aegis_maximum = maximum };
        }
        pub fn len(self: *const Self) usize {
            return self.aegis_used;
        }
        /// How many it holds as it stands; a full one fails its next append with `Full`.
        pub fn capacity(self: *const Self) usize {
            return self.aegis_storage.len;
        }
        /// Whether the next append or push would fail with `Full`.
        pub fn isFull(self: *const Self) bool {
            return self.aegis_used == self.aegis_storage.len;
        }
        fn index(self: *const Self, offset: usize) usize {
            const remaining = self.aegis_storage.len - self.aegis_head;
            return if (offset < remaining) self.aegis_head + offset else offset - remaining;
        }
        pub fn push(self: *Self, value: *T) PushError!void {
            if (self.aegis_used == self.aegis_storage.len) return error.Full;
            move.into(T, value, &self.aegis_storage[self.index(self.aegis_used)]);
            self.aegis_used += 1;
        }
        pub fn peek(self: *Self) PopError!*T {
            if (self.aegis_used == 0) return error.Empty;
            return &self.aegis_storage[self.aegis_head];
        }
        pub fn pop(self: *Self, destination: *T) PopError!void {
            move.into(T, try self.peek(), destination);
            self.aegis_head = if (self.aegis_head == self.aegis_storage.len - 1) 0 else self.aegis_head + 1;
            self.aegis_used -= 1;
        }
        pub fn overwrite(self: *Self, value: *T, evicted: *T) bool {
            const full = self.aegis_used == self.aegis_storage.len;
            // unreachable: a full nonzero ring has a live head.
            if (full) self.pop(evicted) catch unreachable;
            // unreachable: eviction or nonfull admission leaves a free slot.
            self.push(value) catch unreachable;
            return full;
        }
        /// OOM preserves owners, cursors and borrows. Successful reserve linearizes FIFO storage.
        pub fn reserve(self: *Self, wanted: usize) ReserveError!void {
            if (wanted > self.aegis_maximum) return error.CapacityExceeded;
            if (wanted <= self.aegis_storage.len) return;
            const gpa = self.aegis_gpa orelse return error.CallerBacked;
            const storage = try gpa.alloc(T, wanted);
            for (0..self.aegis_used) |i| move.into(T, &self.aegis_storage[self.index(i)], &storage[i]);
            gpa.free(self.aegis_storage);
            self.aegis_storage = storage;
            self.aegis_head = 0;
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.aegis_used != 0) {
                var value: T = undefined;
                // unreachable: loop condition proves a live head.
                self.pop(&value) catch unreachable;
                cleanup(&value);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            if (self.aegis_gpa) |gpa| gpa.free(self.aegis_storage);
            self.* = undefined;
        }
    };
}
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
        aegis_maximum: Repr,
        pub const CheckError = error{LimitExceeded};
        pub fn init(maximum: Repr) Self {
            return .{ .aegis_maximum = maximum };
        }
        /// Whether `amount` is over the maximum; an amount equal to it is within.
        pub fn exceeds(self: Self, amount: Repr) bool {
            return amount > self.aegis_maximum;
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
        aegis_ceiling: Repr,
        /// Private: outstanding reservations plus permanently consumed work; never above the ceiling.
        aegis_taken: Repr = 0,
        /// Private: Debug-only count of reservations not yet released, consumed or moved on.
        aegis_unsettled: if (diagnostics) usize else void = if (diagnostics) 0 else {},
        pub const ReserveError = error{LimitExceeded};
        pub fn init(maximum_amount: Repr) Self {
            return .{ .aegis_ceiling = maximum_amount };
        }
        fn charge(self: *Self, amount: Repr) ReserveError!void {
            if (amount > self.aegis_ceiling - self.aegis_taken) return error.LimitExceeded;
            self.aegis_taken += amount;
        }
        pub fn reserve(self: *Self, amount: Repr) ReserveError!Reservation {
            try self.charge(amount);
            if (diagnostics) self.aegis_unsettled += 1;
            return .{ .aegis_budget = self, .aegis_amount = amount };
        }
        /// An ordinary reservation that leaves at least `kept` unreserved. A path that must still be admitted
        /// when the ordinary ones have filled the budget, such as the cancellation or termination of work
        /// already admitted, takes plain `reserve` and finds the room kept for it. The budget never holds more
        /// than its maximum, so the total stays bounded; the kept amount is part of that maximum.
        pub fn reserveKeeping(self: *Self, amount: Repr, kept: Repr) ReserveError!Reservation {
            const free = self.aegis_ceiling - self.aegis_taken;
            if (kept > free or amount > free - kept) return error.LimitExceeded;
            self.aegis_taken += amount;
            if (diagnostics) self.aegis_unsettled += 1;
            return .{ .aegis_budget = self, .aegis_amount = amount };
        }
        pub fn consume(self: *Self, amount: Repr) ReserveError!void {
            try self.charge(amount);
        }
        /// The configured maximum.
        pub fn maximum(self: *const Self) Repr {
            return self.aegis_ceiling;
        }
        /// What reservations hold and consumption has used.
        pub fn charged(self: *const Self) Repr {
            return self.aegis_taken;
        }
        /// What a plain reservation can still take.
        pub fn remaining(self: *const Self) Repr {
            return self.aegis_ceiling - self.aegis_taken;
        }
        /// A Debug witness: whether every reservation this budget gave has been released or
        /// consumed (a move hands one on, still open). A reservation dropped without either
        /// leaves it false, which a test asserts after the work it charged. A build without
        /// diagnostics keeps no count and answers true.
        pub fn settled(self: *const Self) bool {
            return if (diagnostics) self.aegis_unsettled == 0 else true;
        }
        pub const Reservation = struct {
            /// Private: stable borrowed budget.
            aegis_budget: *Self,
            /// Private: charged amount.
            aegis_amount: Repr,
            /// Private: Debug-only exactly-once witness; copies remain caller violations.
            aegis_live: if (diagnostics) bool else void = if (diagnostics) true else {},
            pub fn release(self: *Reservation) void {
                if (diagnostics) {
                    std.debug.assert(self.aegis_live);
                    self.aegis_live = false;
                }
                if (self.aegis_amount > self.aegis_budget.aegis_taken) @panic("budget reservation underflow");
                self.aegis_budget.aegis_taken -= self.aegis_amount;
                if (diagnostics) self.aegis_budget.aegis_unsettled -= 1;
            }
            /// Ends the reservation with its amount kept as consumed work, as `Budget.consume`
            /// charges it: what it was reserved for was done, and the budget never takes it back.
            /// An allocation charged before it is made keeps its charge this way once it succeeds.
            pub fn consume(self: *Reservation) void {
                if (diagnostics) {
                    std.debug.assert(self.aegis_live);
                    self.aegis_live = false;
                    self.aegis_budget.aegis_unsettled -= 1;
                }
            }
            pub fn moveInto(self: *Reservation, destination: *Reservation) void {
                if (diagnostics) {
                    std.debug.assert(self.aegis_live);
                    std.debug.assert(self != destination);
                }
                destination.* = .{ .aegis_budget = self.aegis_budget, .aegis_amount = self.aegis_amount };
                if (diagnostics) self.aegis_live = false;
            }
        };
    };
}
