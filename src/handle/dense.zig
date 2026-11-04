//! Dense values with two-way slot links, each part on a region of its own, so growth moves
//! nothing. Swap removal moves the last value into the hole, and invalidates that value's borrows.
const std = @import("std");
const Region = @import("../Region.zig");
const Domain = @import("Domain.zig");
const SlotPool = @import("slot_pool.zig").SlotPool;
const move = @import("../move.zig");
const overlap = @import("overlap.zig");
pub fn DenseSlotMap(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        const Primary = SlotPool(usize, Tag, .{ .generation = u64 });
        pub const Key = Primary.Key;
        /// The three regions a map grows on, each its own: the key slots, the values and the
        /// values' keys.
        pub const Regions = struct { slots: Region, values: Region, keys: Region };
        pub const InitError = Primary.InitError;
        pub const InsertError = Primary.InsertError;
        pub const KeyError = Primary.KeyError;
        primary: Primary,
        /// Private: the regions the values and their keys grow on.
        value_region: Region,
        key_region: Region,
        /// Private: the first value and the first value's key.
        values: [*]T,
        keys: [*]Key,
        /// Private: the values and keys pushed so far.
        value_room: usize = 0,
        key_room: usize = 0,
        /// Private: the live values, the first `used` of them.
        used: usize = 0,
        /// The map owns `regions` from here on.
        pub fn init(regions: Regions, instance: Domain.Instance) InitError!Self {
            return .{
                .primary = try Primary.init(regions.slots, instance),
                .value_region = regions.values,
                .key_region = regions.keys,
                .values = @ptrFromInt(std.mem.alignForward(usize, regions.values.top, @alignOf(T))), // safe: the values start at the region's top, aligned as its pushes align them
                .keys = @ptrFromInt(std.mem.alignForward(usize, regions.keys.top, @alignOf(Key))), // safe: the keys start at the region's top, aligned as its pushes align them
            };
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
        pub fn insert(self: *Self, source: *T) InsertError!Key {
            if (overlap.overlapsOwner(T, source, self) or overlap.overlaps(T, source, self.values[0..self.value_room])) return error.AliasedStorage;
            // Room first, so a failure leaves the map as it was; room left over serves the next insert.
            if (self.used == self.value_room) {
                _ = try self.value_region.create(T);
                self.value_room += 1;
            }
            if (self.used == self.key_room) {
                _ = try self.key_region.create(Key);
                self.key_room += 1;
            }
            var position = self.used;
            const key = try self.primary.insert(&position);
            move.intoPoisoning(T, source, &self.values[self.used]);
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
            if (overlap.overlapsOwner(T, destination, self) or overlap.overlaps(T, destination, self.values[0..self.value_room])) return error.AliasedStorage;
            var position: usize = undefined;
            try self.primary.remove(key, &position);
            move.intoPoisoning(T, &self.values[position], destination);
            self.used -= 1;
            if (position != self.used) {
                move.intoPoisoning(T, &self.values[self.used], &self.values[position]);
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
            self.primary.deinit(ignore);
            self.value_region.deinit();
            self.key_region.deinit();
            self.* = undefined;
        }
    };
}
