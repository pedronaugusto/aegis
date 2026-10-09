//! Full-key associations. Every resolve requires the primary's liveness witness.
const std = @import("std");
const transfer = @import("transfer.zig");
pub fn SecondaryMap(comptime KeyType: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Entry = struct { key: KeyType, value: V = undefined, live: bool = false, next: usize = std.math.maxInt(usize) };
        pub const Key = KeyType;
        pub const PutError = std.mem.Allocator.Error || error{ InvalidKey, AlreadyPresent, AliasedStorage };
        pub const KeyError = error{ InvalidKey, Missing, AliasedStorage };
        gpa: std.mem.Allocator,
        index: std.AutoHashMapUnmanaged(Key, usize) = .empty,
        entries: []Entry = &.{},
        free_head: usize = std.math.maxInt(usize),
        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa };
        }
        pub fn put(self: *Self, primary: anytype, key: Key, source: *V) PutError!void {
            if (!primary.contains(key)) return error.InvalidKey;
            if (self.index.contains(key)) return error.AlreadyPresent;
            if (transfer.overlapsOwner(V, source, self) or transfer.overlaps(V, source, self.entries)) return error.AliasedStorage;
            try self.index.ensureUnusedCapacity(self.gpa, 1);
            if (self.free_head == std.math.maxInt(usize)) {
                const count = std.math.add(usize, self.entries.len, self.entries.len / 2 + 1) catch return error.OutOfMemory;
                const next = try self.gpa.alloc(Entry, count);
                for (0..self.entries.len) |i| {
                    next[i] = .{ .key = if (self.entries[i].live) self.entries[i].key else undefined, .live = self.entries[i].live, .next = self.entries[i].next };
                    if (next[i].live) transfer.move(V, &self.entries[i].value, &next[i].value);
                }
                var head = self.free_head;
                var i = count;
                while (i > self.entries.len) {
                    i -= 1;
                    next[i] = .{ .key = undefined, .next = head };
                    head = i;
                }
                self.gpa.free(self.entries);
                self.entries = next;
                self.free_head = head;
            }
            const position = self.free_head;
            self.free_head = self.entries[position].next;
            self.entries[position] = .{ .key = key, .live = true };
            transfer.move(V, source, &self.entries[position].value);
            self.index.putAssumeCapacity(key, position);
        }
        pub inline fn get(self: *Self, primary: anytype, key: Key) KeyError!*V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.index.get(key) orelse return error.Missing;
            return &self.entries[position].value;
        }
        pub inline fn getConst(self: *const Self, primary: anytype, key: Key) KeyError!*const V {
            if (!primary.contains(key)) return error.InvalidKey;
            const position = self.index.get(key) orelse return error.Missing;
            return &self.entries[position].value;
        }
        /// Removal needs no witness: stale associations still own values needing cleanup.
        pub fn remove(self: *Self, key: Key, destination: *V) KeyError!void {
            const position = self.index.get(key) orelse return error.Missing;
            if (transfer.overlapsOwner(V, destination, self) or transfer.overlaps(V, destination, self.entries)) return error.AliasedStorage;
            _ = self.index.remove(key);
            transfer.move(V, &self.entries[position].value, destination);
            self.entries[position].live = false;
            self.entries[position].next = self.free_head;
            self.free_head = position;
        }
        /// Ascending association-slot order; may also reclaim stale associations.
        pub fn prune(self: *Self, primary: anytype, comptime cleanup: fn (*V) void) void {
            for (self.entries) |*entry| {
                if (!entry.live or primary.contains(entry.key)) continue;
                var detached: V = undefined;
                self.remove(entry.key, &detached) catch unreachable; // unreachable: the live association is indexed and detached storage is disjoint
                cleanup(&detached);
            }
        }
        pub fn clear(self: *Self, comptime cleanup: fn (*V) void) void {
            for (self.entries) |*entry| {
                if (!entry.live) continue;
                var detached: V = undefined;
                self.remove(entry.key, &detached) catch unreachable; // unreachable: the live association is indexed and detached storage is disjoint
                cleanup(&detached);
            }
        }
        pub fn deinit(self: *Self, comptime cleanup: fn (*V) void) void {
            self.clear(cleanup);
            self.index.deinit(self.gpa);
            self.gpa.free(self.entries);
            self.* = undefined;
        }
    };
}
