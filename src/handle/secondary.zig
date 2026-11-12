//! Full-key associations. Every resolve requires the primary's liveness witness: the primary map itself,
//! typed, a keyed `SlotPool` or `DenseSlotMap` whose keys this map holds. The values live on a region
//! of their own and never move; only the index rehashes.
const std = @import("std");
const Region = @import("../Region.zig");
const move = @import("../move.zig");
const overlap = @import("overlap.zig");
pub fn SecondaryMap(comptime Primary: type, comptime V: type) type {
    return struct {
        const Self = @This();
        pub const Key = Primary.Key;
        const Entry = struct { key: Key, value: V = undefined, live: bool = false, next: usize = std.math.maxInt(usize) };
        pub const PutError = std.mem.Allocator.Error || Region.Error || error{ InvalidKey, AlreadyPresent, AliasedStorage };
        pub const KeyError = error{ InvalidKey, Missing, AliasedStorage };
        /// The index's allocator.
        gpa: std.mem.Allocator,
        /// Private: each live key's entry.
        aegis_index: std.AutoHashMapUnmanaged(Key, usize) = .empty,
        /// Private: the region the entries grow on.
        aegis_region: Region,
        /// Private: the first entry.
        aegis_first: [*]Entry,
        /// Private: the entries pushed so far.
        aegis_room: usize = 0,
        aegis_free_head: usize = std.math.maxInt(usize),
        /// The map owns `entries` from here on; the index allocates from `gpa`.
        pub fn init(gpa: std.mem.Allocator, entries: Region) Self {
            return .{ .gpa = gpa, .aegis_region = entries, .aegis_first = @ptrFromInt(std.mem.alignForward(usize, entries.top, @alignOf(Entry))) }; // safe: the entries start at the region's top, aligned as its pushes align them
        }
        fn storage(self: *const Self) []Entry {
            return self.aegis_first[0..self.aegis_room];
        }
        pub fn put(self: *Self, primary: *const Primary, key: Key, source: *V) PutError!void {
            if (!primary.contains(key)) return error.InvalidKey;
            if (self.aegis_index.contains(key)) return error.AlreadyPresent;
            if (overlap.overlapsOwner(V, source, self) or overlap.overlaps(V, source, self.storage())) return error.AliasedStorage;
            try self.aegis_index.ensureUnusedCapacity(self.gpa, 1);
            if (self.aegis_free_head == std.math.maxInt(usize)) {
                const entry = try self.aegis_region.create(Entry);
                entry.* = .{ .key = undefined };
                self.aegis_free_head = self.aegis_room;
                self.aegis_room += 1;
            }
            const entries = self.storage();
            const position = self.aegis_free_head;
            self.aegis_free_head = entries[position].next;
            entries[position] = .{ .key = key, .live = true };
            move.intoPoisoning(V, source, &entries[position].value);
            self.aegis_index.putAssumeCapacity(key, position);
        }
        pub inline fn get(self: *Self, primary: *const Primary, key: Key) KeyError!*V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.aegis_index.get(key) orelse return error.Missing;
            return &self.aegis_first[position].value;
        }
        pub inline fn getConst(self: *const Self, primary: *const Primary, key: Key) KeyError!*const V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.index.get(key) orelse return error.Missing;
            return &self.first[position].value;
        }
        /// Removal needs no witness: stale associations still own values needing cleanup.
        pub fn remove(self: *Self, key: Key, destination: *V) KeyError!void {
            const position = self.aegis_index.get(key) orelse return error.Missing;
            if (overlap.overlapsOwner(V, destination, self) or overlap.overlaps(V, destination, self.storage())) return error.AliasedStorage;
            _ = self.aegis_index.remove(key);
            const entry = &self.aegis_first[position];
            move.intoPoisoning(V, &entry.value, destination);
            entry.live = false;
            entry.next = self.aegis_free_head;
            self.aegis_free_head = position;
        }
        /// Ascending association-slot order; may also reclaim stale associations.
        pub fn prune(self: *Self, primary: *const Primary, comptime cleanup: fn (*V) void) void {
            for (self.storage()) |*entry| {
                if (!entry.live or primary.contains(entry.key)) continue;
                var detached: V = undefined;
                self.remove(entry.key, &detached) catch unreachable; // unreachable: the live association is indexed and detached storage is disjoint
                cleanup(&detached);
            }
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*V) void) void {
            for (self.storage()) |*entry| {
                if (!entry.live) continue;
                var detached: V = undefined;
                self.remove(entry.key, &detached) catch unreachable; // unreachable: the live association is indexed and detached storage is disjoint
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*V) void) void {
            self.clear(cleanup);
            self.aegis_index.deinit(self.gpa);
            self.aegis_region.deinit();
            self.* = undefined;
        }
    };
}
