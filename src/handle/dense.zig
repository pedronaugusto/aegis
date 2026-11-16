//! Dense values with two-way slot links, each part on a region of its own, so growth moves
//! nothing. Swap removal moves the last value into the hole, and invalidates that value's borrows.
const assert = @import("../assert.zig");
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
        aegis_primary: Primary,
        /// Private: the regions the values and their keys grow on.
        aegis_value_region: Region,
        aegis_key_region: Region,
        /// Private: the values and the keys pushed so far, each at its region's top.
        aegis_values: []T = &.{},
        aegis_keys: []Key = &.{},
        /// Private: the live values, the first `used` of them.
        aegis_used: usize = 0,
        /// The map owns `regions` from here on.
        pub fn init(regions: Regions, instance: Domain.Instance) InitError!Self {
            return .{
                .aegis_primary = try Primary.init(regions.slots, instance),
                .aegis_value_region = regions.values,
                .aegis_key_region = regions.keys,
            };
        }
        fn ignore(_: *usize) void {}
        pub fn items(self: *Self) []T {
            return self.aegis_values[0..self.aegis_used];
        }
        pub fn itemsConst(self: *const Self) []const T {
            return self.aegis_values[0..self.aegis_used];
        }
        pub fn len(self: *const Self) usize {
            return self.aegis_used;
        }
        pub fn insert(self: *Self, source: *T) InsertError!Key {
            if (overlap.overlapsOwner(T, source, self) or overlap.overlaps(T, source, self.aegis_values)) return error.AliasedStorage;
            // Room first, so a failure leaves the map as it was; room left over serves the next insert.
            if (self.aegis_used == self.aegis_values.len) self.aegis_values = try self.aegis_value_region.extend(T, self.aegis_values, 1);
            if (self.aegis_used == self.aegis_keys.len) self.aegis_keys = try self.aegis_key_region.extend(Key, self.aegis_keys, 1);
            var position = self.aegis_used;
            const key = try self.aegis_primary.insert(&position);
            move.intoPoisoning(T, source, &self.aegis_values[self.aegis_used]);
            self.aegis_keys[self.aegis_used] = key;
            self.aegis_used += 1;
            return key;
        }
        pub inline fn contains(self: *const Self, key: Key) bool {
            return self.aegis_primary.contains(key);
        }
        pub inline fn get(self: *Self, key: Key) KeyError!*T {
            const i = (try self.aegis_primary.get(key)).*;
            return &self.aegis_values[i];
        }
        pub inline fn getConst(self: *const Self, key: Key) KeyError!*const T {
            const i = (try self.aegis_primary.getConst(key)).*;
            return &self.aegis_values[i];
        }
        pub fn remove(self: *Self, key: Key, destination: *T) KeyError!void {
            if (!self.contains(key)) return error.InvalidKey;
            if (overlap.overlapsOwner(T, destination, self) or overlap.overlaps(T, destination, self.aegis_values)) return error.AliasedStorage;
            var position: usize = undefined;
            try self.aegis_primary.remove(key, &position);
            move.intoPoisoning(T, &self.aegis_values[position], destination);
            self.aegis_used -= 1;
            if (position != self.aegis_used) {
                move.intoPoisoning(T, &self.aegis_values[self.aegis_used], &self.aegis_values[position]);
                self.aegis_keys[position] = self.aegis_keys[self.aegis_used];
                (self.aegis_primary.get(self.aegis_keys[position]) catch assert.never("the live swapped key retains its primary association")).* = position;
            }
        }
        /// Reverse dense order; cleanup receives detached values, never a stored pointer.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            while (self.aegis_used != 0) {
                var detached: T = undefined;
                self.remove(self.aegis_keys[self.aegis_used - 1], &detached) catch assert.never("the last dense entry is live and detached storage is disjoint");
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            self.aegis_primary.deinit(ignore);
            self.aegis_value_region.deinit();
            self.aegis_key_region.deinit();
            self.* = undefined;
        }
    };
}
