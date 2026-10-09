//! Allocating generational owner. Successful reserve invalidates every value borrow.
const std = @import("std");
const Domain = @import("Domain.zig");
const pool = @import("pool.zig");
const transfer = @import("transfer.zig");
pub fn SlotMap(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        pub const Storage = pool.Pool(T, Tag);
        pub const Key = Storage.Key;
        pub const Options = struct { capacity: usize = 0, max_capacity: usize = std.math.maxInt(usize) };
        pub const InitError = std.mem.Allocator.Error || Storage.InitError || error{CapacityExceeded};
        pub const ReserveError = std.mem.Allocator.Error || error{CapacityExceeded};
        pub const InsertError = ReserveError || Storage.InsertError;
        pub const KeyError = Storage.KeyError;
        gpa: std.mem.Allocator,
        storage: Storage,
        max_capacity: usize,
        pub fn init(gpa: std.mem.Allocator, instance: Domain.Instance, options: Options) InitError!Self {
            if (options.capacity > options.max_capacity) return error.CapacityExceeded;
            if (instance.serial == 0) return error.InvalidInstance;
            const slots = try gpa.alloc(Storage.Slot, options.capacity);
            errdefer gpa.free(slots);
            return .{ .gpa = gpa, .storage = try Storage.initBuffer(slots, instance), .max_capacity = options.max_capacity };
        }
        pub fn len(self: *const Self) usize {
            return self.storage.len;
        }
        pub fn capacity(self: *const Self) usize {
            return self.storage.slots.len;
        }
        pub fn reserve(self: *Self, capacity_needed: usize) ReserveError!void {
            if (capacity_needed <= self.capacity()) return;
            if (capacity_needed > self.max_capacity) return error.CapacityExceeded;
            const next = try self.gpa.alloc(Storage.Slot, capacity_needed);
            // No failures follow allocation: publish only after every live value moves.
            for (self.storage.slots, 0..) |*old, i| {
                next[i] = .{ .generation = old.generation, .next = old.next, .state = old.state };
                if (old.state == .live) transfer.move(T, &old.value, &next[i].value);
            }
            var head = self.storage.free_head;
            var i = capacity_needed;
            while (i > self.capacity()) {
                i -= 1;
                next[i] = .{ .next = head };
                head = i;
            }
            self.gpa.free(self.storage.slots);
            self.storage.slots = next;
            self.storage.free_head = head;
        }
        pub fn insert(self: *Self, source: *T) InsertError!Key {
            if (transfer.overlaps(T, source, self.storage.slots)) return error.AliasedStorage;
            if (self.storage.free_head == std.math.maxInt(usize)) {
                const old = self.capacity();
                if (old == self.max_capacity) return error.Full;
                const grown = std.math.add(usize, old, old / 2 + 1) catch self.max_capacity;
                try self.reserve(@min(grown, self.max_capacity));
            }
            return self.storage.insert(source);
        }
        pub inline fn contains(self: *const Self, key: Key) bool {
            return self.storage.contains(key);
        }
        pub inline fn get(self: *Self, key: Key) KeyError!*T {
            return self.storage.get(key);
        }
        pub inline fn getConst(self: *const Self, key: Key) KeyError!*const T {
            return self.storage.getConst(key);
        }
        pub fn remove(self: *Self, key: Key, destination: *T) KeyError!void {
            return self.storage.remove(key, destination);
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            self.storage.clear(cleanup);
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            self.gpa.free(self.storage.slots);
            self.* = undefined;
        }
    };
}
