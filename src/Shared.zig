//! Counted shared ownership of one allocated value.
const std = @import("std");
const builtin = @import("builtin");
const interior = @import("interior.zig");
const diagnostics = builtin.mode == .debug;

/// Moves `source` into `destination` through `moveInto` when `T` declares it, else by assignment.
fn transfer(comptime T: type, source: *T, destination: *T) void {
    const has_move = switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum" => @hasDecl(T, "moveInto"),
        else => false,
    };
    if (has_move) source.moveInto(destination) else destination.* = source.*;
}

/// One allocated `T` and an atomic count of the handles that own it; the last `release` runs `cleanup`
/// once and frees the block. Cleanup is static, infallible and nonblocking, and runs on whichever task
/// releases last. A handle is one pointer: each handle is released once, and a copy made with `=` instead
/// of `retain` is a caller bug (Debug diagnoses a handle released twice). A `T` that declares
/// `pub const interior_lock = true` is handed out mutable; any other is const.
pub fn Shared(comptime T: type, comptime cleanup: fn (*T) void) type {
    return struct {
        const Self = @This();
        const Block = struct {
            /// Private: handles that own the value; zero only while being freed.
            count: std.atomic.Value(usize) = .init(1),
            /// Private: the allocator the block came from, kept to free it.
            gpa: std.mem.Allocator,
            /// Private: the value, alive while any handle is.
            data: T,
        };
        /// The pointer handed out: mutable only for a type that locks itself.
        pub const Ref = interior.Handout(T);
        /// Past this many handles `retain` fails stop: the count is a resource limit, never wrapped.
        pub const maximum_handles = std.math.maxInt(usize) / 2;
        /// Private: the shared block, stable until the last handle is released.
        block: *Block,
        /// Private: Debug-only exactly-once witness for this handle value.
        live: if (diagnostics) bool else void = if (diagnostics) true else {},

        /// A new block holding `value`, with one handle.
        pub fn create(gpa: std.mem.Allocator, value: T) std.mem.Allocator.Error!Self {
            const block = try gpa.create(Block);
            block.* = .{ .gpa = gpa, .data = value };
            return .{ .block = block };
        }

        /// A new block that takes the payload from `source` by `moveInto` when `T` declares it, else by
        /// assignment. On an allocation error `source` is untouched; on success it is consumed.
        pub fn createFrom(gpa: std.mem.Allocator, source: *T) std.mem.Allocator.Error!Self {
            const block = try gpa.create(Block);
            block.gpa = gpa;
            block.count = .init(1);
            transfer(T, source, &block.data);
            return .{ .block = block };
        }

        /// Another handle to the same value. Release both.
        pub fn retain(self: *const Self) Self {
            if (diagnostics) std.debug.assert(self.live);
            const before = self.block.count.fetchAdd(1, .monotonic);
            if (before >= maximum_handles) @panic("shared owner handle count overflow");
            return .{ .block = self.block };
        }

        /// The value, for as long as this handle is held.
        pub fn get(self: *const Self) Ref {
            if (diagnostics) std.debug.assert(self.live);
            return &self.block.data;
        }

        /// Gives this handle up; the last one runs cleanup and frees the block. The handle is consumed.
        pub fn release(self: *Self) void {
            if (diagnostics) {
                std.debug.assert(self.live);
                self.live = false;
            }
            const block = self.block;
            if (block.count.fetchSub(1, .release) != 1) return;
            // Acquire what every earlier release published before the value is cleaned.
            _ = block.count.load(.acquire);
            cleanup(&block.data);
            const gpa = block.gpa;
            gpa.destroy(block);
        }
    };
}
