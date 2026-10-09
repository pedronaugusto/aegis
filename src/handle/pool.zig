//! Fixed stable slots. Caller owns storage; keys validate in every build mode.
const std = @import("std");
const Domain = @import("Domain.zig");
const transfer = @import("transfer.zig");
const none = std.math.maxInt(usize);
pub fn Pool(comptime T: type, comptime Tag: type) type {
    return WithGeneration(T, Tag, u64);
}
// Internal lowered-width instantiation supports exhaustive retirement tests.
pub fn WithGeneration(comptime T: type, comptime Tag: type, comptime G: type) type {
    return struct {
        const Self = @This();
        pub const Key = struct {
            pub const Brand = Tag;
            instance: Domain.Instance,
            index: usize,
            generation: G,
        };
        pub const Slot = struct {
            generation: G = 1,
            next: usize = none,
            state: enum { free, live, retired } = .free,
            value: T = undefined,
        };
        comptime {
            std.debug.assert(@sizeOf(Key) <= 48);
            std.debug.assert(@sizeOf(Self) <= 80);
        }
        pub const InitError = error{InvalidInstance};
        pub const KeyError = error{ InvalidKey, AliasedStorage };
        pub const InsertError = error{ Full, AliasedStorage };
        slots: []Slot,
        instance: Domain.Instance,
        free_head: usize,
        len: usize = 0,
        retired: usize = 0,
        pub fn initBuffer(slots: []Slot, instance: Domain.Instance) InitError!Self {
            if (instance.serial == 0) return error.InvalidInstance;
            for (slots, 0..) |*slot, i| slot.* = .{ .next = if (i + 1 < slots.len) i + 1 else none };
            return .{ .slots = slots, .instance = instance, .free_head = if (slots.len == 0) none else 0 };
        }
        pub inline fn insert(self: *Self, source: *T) InsertError!Key {
            if (transfer.overlapsOwner(T, source, self)) return error.AliasedStorage;
            const slots = self.slots;
            if (transfer.overlaps(T, source, slots)) return error.AliasedStorage;
            if (self.free_head == none) return error.Full;
            const i = self.free_head;
            const slot = &slots[i];
            self.free_head = slot.next;
            transfer.move(T, source, &slot.value);
            slot.state = .live;
            self.len += 1;
            return .{ .instance = self.instance, .index = i, .generation = slot.generation };
        }
        pub inline fn contains(self: *const Self, key: Key) bool {
            if (self.instance.namespace != key.instance.namespace or self.instance.serial != key.instance.serial or key.index >= self.slots.len) return false;
            const slot = &self.slots[key.index];
            return slot.state == .live and slot.generation == key.generation;
        }
        pub inline fn get(self: *Self, key: Key) KeyError!*T {
            if (!self.contains(key)) return error.InvalidKey;
            return &self.slots[key.index].value;
        }
        pub inline fn getConst(self: *const Self, key: Key) KeyError!*const T {
            if (!self.contains(key)) return error.InvalidKey;
            return &self.slots[key.index].value;
        }
        pub inline fn remove(self: *Self, key: Key, destination: *T) KeyError!void {
            if (!self.contains(key)) return error.InvalidKey;
            if (transfer.overlapsOwner(T, destination, self) or transfer.overlaps(T, destination, self.slots)) return error.AliasedStorage;
            const slot = &self.slots[key.index];
            transfer.move(T, &slot.value, destination);
            self.invalidate(slot, key.index);
        }
        fn invalidate(self: *Self, slot: *Slot, i: usize) void {
            self.len -= 1;
            if (slot.generation == std.math.maxInt(G)) {
                slot.state = .retired;
                self.retired += 1;
            } else {
                slot.generation += 1;
                slot.state = .free;
                slot.next = self.free_head;
                self.free_head = i;
            }
        }
        /// Ascending slot order. Cleanup sees detached values; reentry is forbidden.
        pub fn clear(self: *Self, comptime cleanup: fn (*T) void) void {
            for (self.slots, 0..) |*slot, i| {
                if (slot.state != .live) continue;
                var detached: T = undefined;
                transfer.move(T, &slot.value, &detached);
                self.invalidate(slot, i);
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*T) void) void {
            self.clear(cleanup);
            self.* = undefined;
        }
    };
}
