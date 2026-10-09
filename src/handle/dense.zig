//! Dense values with two-way slot links. Swap removal invalidates affected borrows.
const std = @import("std");
const Domain = @import("Domain.zig");
const maps = @import("slot_map.zig");
const transfer = @import("transfer.zig");
pub fn DenseSlotMap(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        const Primary = maps.SlotMap(usize, Tag);
        pub const Key = Primary.Key;
        pub const Options = Primary.Options;
        pub const InitError = Primary.InitError;
        pub const ReserveError = Primary.ReserveError;
        pub const InsertError = Primary.InsertError;
        pub const KeyError = Primary.KeyError;
        primary: Primary,
        values: []T,
        keys: []Key,
        used: usize = 0,
        pub fn init(gpa: std.mem.Allocator, instance: Domain.Instance, options: Options) InitError!Self {
            var primary = try Primary.init(gpa, instance, options);
            errdefer primary.deinit(ignore);
            const values = try gpa.alloc(T, options.capacity);
            errdefer gpa.free(values);
            const keys = try gpa.alloc(Key, options.capacity);
            return .{ .primary = primary, .values = values, .keys = keys };
        }
        fn ignore(_: *usize) void {}
        pub fn items(self: *Self) []T {
            return self.values[0..self.used];
        }
        pub fn itemsConst(self: *const Self) []const T {
            return self.values[0..self.used];
        }
        pub fn len(self: *const Self) usize {
            return self.used;
        }
        pub fn reserve(self: *Self, count: usize) ReserveError!void {
            if (count <= self.values.len and count <= self.primary.capacity()) return;
            if (count > self.primary.max_capacity) return error.CapacityExceeded;
            const next_count = @max(count, self.values.len);
            const gpa = self.primary.gpa;
            const values = try gpa.alloc(T, next_count);
            errdefer gpa.free(values);
            const keys = try gpa.alloc(Key, next_count);
            errdefer gpa.free(keys);
            try self.primary.reserve(count);
            for (0..self.used) |i| transfer.move(T, &self.values[i], &values[i]);
            @memcpy(keys[0..self.used], self.keys[0..self.used]);
            gpa.free(self.values);
            gpa.free(self.keys);
            self.values = values;
            self.keys = keys;
        }
        pub fn insert(self: *Self, source: *T) InsertError!Key {
            if (transfer.overlapsOwner(T, source, self) or transfer.overlaps(T, source, self.values)) return error.AliasedStorage;
            if (self.used == self.values.len or self.primary.storage.free_head == std.math.maxInt(usize)) {
                const old = self.primary.capacity();
                if (old == self.primary.max_capacity) return error.Full;
                const grown = std.math.add(usize, old, old / 2 + 1) catch self.primary.max_capacity;
                try self.reserve(@min(grown, self.primary.max_capacity));
            }
            var position = self.used;
            const key = try self.primary.insert(&position);
            transfer.move(T, source, &self.values[self.used]);
            self.keys[self.used] = key;
            self.used += 1;
            return key;
        }
        pub inline fn contains(self: *const Self, key: Key) bool {
            return self.primary.contains(key);
        }
        pub inline fn get(self: *Self, key: Key) KeyError!*T {
            const i = (try self.primary.get(key)).*;
            return &self.values[i];
        }
        pub inline fn getConst(self: *const Self, key: Key) KeyError!*const T {
            const i = (try self.primary.getConst(key)).*;
            return &self.values[i];
        }
        pub fn remove(self: *Self, key: Key, destination: *T) KeyError!void {
            if (!self.contains(key)) return error.InvalidKey;
            if (transfer.overlapsOwner(T, destination, self) or transfer.overlaps(T, destination, self.values)) return error.AliasedStorage;
            var position: usize = undefined;
            try self.primary.remove(key, &position);
            transfer.move(T, &self.values[position], destination);
            self.used -= 1;
            if (position != self.used) {
                transfer.move(T, &self.values[self.used], &self.values[position]);
                self.keys[position] = self.keys[self.used];
                (self.primary.get(self.keys[position]) catch unreachable).* = position; // unreachable: the live swapped key retains its primary association
            }
        }
        /// Reverse dense order; cleanup receives detached values, never a stored pointer.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.used != 0) {
                var detached: T = undefined;
                self.remove(self.keys[self.used - 1], &detached) catch unreachable; // unreachable: the last dense entry is live and detached storage is disjoint
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            const gpa = self.primary.gpa;
            self.primary.deinit(ignore);
            gpa.free(self.values);
            gpa.free(self.keys);
            self.* = undefined;
        }
    };
}
