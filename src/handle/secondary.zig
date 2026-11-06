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
        index: std.AutoHashMapUnmanaged(Key, usize) = .empty,
        /// Private: the region the entries grow on.
        region: Region,
        /// Private: the first entry.
        first: [*]Entry,
        /// Private: the entries pushed so far.
        room: usize = 0,
        free_head: usize = std.math.maxInt(usize),
        /// The map owns `entries` from here on; the index allocates from `gpa`.
        pub fn init(gpa: std.mem.Allocator, entries: Region) Self {
            return .{ .gpa = gpa, .region = entries, .first = @ptrFromInt(std.mem.alignForward(usize, entries.top, @alignOf(Entry))) }; // safe: the entries start at the region's top, aligned as its pushes align them
        }
        fn storage(self: *const Self) []Entry {
            return self.first[0..self.room];
        }
        pub fn put(self: *Self, primary: *const Primary, key: Key, source: *V) PutError!void {
            if (!primary.contains(key)) return error.InvalidKey;
            if (self.index.contains(key)) return error.AlreadyPresent;
            if (overlap.overlapsOwner(V, source, self) or overlap.overlaps(V, source, self.storage())) return error.AliasedStorage;
            try self.index.ensureUnusedCapacity(self.gpa, 1);
            if (self.free_head == std.math.maxInt(usize)) {
                const entry = try self.region.create(Entry);
                entry.* = .{ .key = undefined };
                self.free_head = self.room;
                self.room += 1;
            }
            const entries = self.storage();
            const position = self.free_head;
            self.free_head = entries[position].next;
            entries[position] = .{ .key = key, .live = true };
            move.intoPoisoning(V, source, &entries[position].value);
            self.index.putAssumeCapacity(key, position);
        }
        pub inline fn get(self: *Self, primary: *const Primary, key: Key) KeyError!*V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.index.get(key) orelse return error.Missing;
            return &self.first[position].value;
        }
        pub inline fn getConst(self: *const Self, primary: *const Primary, key: Key) KeyError!*const V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.index.get(key) orelse return error.Missing;
            return &self.first[position].value;
        }
        /// Removal needs no witness: stale associations still own values needing cleanup.
        pub fn remove(self: *Self, key: Key, destination: *V) KeyError!void {
            const position = self.index.get(key) orelse return error.Missing;
            if (overlap.overlapsOwner(V, destination, self) or overlap.overlaps(V, destination, self.storage())) return error.AliasedStorage;
            _ = self.index.remove(key);
            const entry = &self.first[position];
            move.intoPoisoning(V, &entry.value, destination);
            entry.live = false;
            entry.next = self.free_head;
            self.free_head = position;
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
            self.index.deinit(self.gpa);
            self.region.deinit();
            self.* = undefined;
        }
    };
}
