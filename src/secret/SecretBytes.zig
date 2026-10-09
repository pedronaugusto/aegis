//! One explicit owner of a full allocator allocation, including non-live slack.
const std = @import("std");
const SecretBytes = @This();

// Private by contract: never copy a live descriptor or truncate its allocation.
gpa: std.mem.Allocator,
allocation: []u8,
used_len: usize,

pub const InitError = std.mem.Allocator.Error;
pub const AdoptError = error{InvalidLength};
pub const ResizeError = error{CapacityExceeded};
pub const ReplaceError = error{ CapacityExceeded, Overlap };
pub const ReserveError = std.mem.Allocator.Error;

/// Allocates and zeros full capacity; the live prefix starts empty.
/// Pair success immediately with defer/errdefer. No automatic cleanup on abort.
pub fn init(gpa: std.mem.Allocator, full_capacity: usize) InitError!SecretBytes {
    const allocation = try gpa.alloc(u8, full_capacity);
    @memset(allocation, 0);
    return .{ .gpa = gpa, .allocation = allocation, .used_len = 0 };
}

/// Takes exclusive ownership of the full allocator-owned slice on success only.
/// Requires a byte allocation releasable with u8 alignment by this allocator.
/// The live prefix must be initialized; slack may be undefined. A slice cannot
/// prove allocator provenance, full extent or exclusivity: those are obligations
/// of the caller. Borrowed memory must never be adopted. Failure changes nothing.
pub fn adopt(gpa: std.mem.Allocator, allocation: []u8, live_len: usize) AdoptError!SecretBytes {
    if (live_len > allocation.len) return error.InvalidLength;
    return .{ .gpa = gpa, .allocation = allocation, .used_len = live_len };
}

/// Number of live bytes.
pub fn len(self: *const SecretBytes) usize {
    return self.used_len;
}

/// Full extent that will be erased before free, including unused slack.
pub fn capacity(self: *const SecretBytes) usize {
    return self.allocation.len;
}

/// Borrows only the initialized live prefix. Ends at successful reserve, move
/// or cleanup; resize/replace can change its content. No concurrent mutation.
pub fn expose(self: *const SecretBytes) []const u8 {
    return self.allocation[0..self.used_len];
}

/// Mutable live-prefix borrow; the caller must erase displaced material.
pub fn exposeMut(self: *SecretBytes) []u8 {
    return self.allocation[0..self.used_len];
}

/// Shrink erases removed live bytes immediately; grow zeros newly live bytes.
/// Never allocates. Failure preserves ownership, content and existing borrows.
pub fn resizeWithinCapacity(self: *SecretBytes, new_len: usize) ResizeError!void {
    if (new_len > self.allocation.len) return error.CapacityExceeded;
    if (new_len < self.used_len) {
        std.crypto.secureZero(u8, self.allocation[new_len..self.used_len]);
    } else {
        @memset(self.allocation[self.used_len..new_len], 0);
    }
    self.used_len = new_len;
}

/// Disjoint input only: rejects overlap with ANY part of the backing allocation,
/// including slack, before mutation in every mode. No implicit capacity growth.
/// Empty input has no occupied bytes. Borrowed input remains caller-owned.
pub fn replace(self: *SecretBytes, bytes: []const u8) ReplaceError!void {
    if (bytes.len > self.allocation.len) return error.CapacityExceeded;
    if (bytes.len != 0 and self.allocation.len != 0) {
        const x = @intFromPtr(self.allocation.ptr); // safe: numerical address comparison only, no dereference
        const y = @intFromPtr(bytes.ptr); // safe: valid input slice address, compared without dereferencing
        // Subtract from the greater address: no end-pointer overflow.
        if (if (x <= y) y - x < self.allocation.len else x - y < bytes.len) return error.Overlap;
    }
    std.crypto.secureZero(u8, self.allocation[0..self.used_len]);
    @memcpy(self.allocation[0..bytes.len], bytes);
    self.used_len = bytes.len;
}

/// Explicit growth: allocate, zero, copy live prefix, erase ENTIRE old capacity,
/// free, then publish new storage. Never resize/remap or transfer a bare slice.
/// OOM preserves the old owner and all its borrows. Success ends old borrows.
/// A request at or below capacity is a no-op and preserves borrows.
pub fn reserve(self: *SecretBytes, new_capacity: usize) ReserveError!void {
    if (new_capacity <= self.allocation.len) return;
    const replacement = try self.gpa.alloc(u8, new_capacity);
    @memset(replacement, 0);
    @memcpy(replacement[0..self.used_len], self.expose());
    eraseAndFree(self.gpa, self.allocation);
    self.allocation = replacement;
}

/// Transfers into uninitialized disjoint descriptor storage, consuming self.
/// Allocation and live bytes move without allocation or copying their content;
/// all source borrows end. Destination must not already own resources and must
/// sit outside this owner's allocation (as must the source descriptor).
pub fn moveInto(self: *SecretBytes, destination: *SecretBytes) void {
    @setRuntimeSafety(true);
    @memcpy(std.mem.asBytes(destination), std.mem.asBytes(self));
    std.crypto.secureZero(u8, std.mem.asBytes(self));
}

/// Erases full capacity BEFORE free in every mode, then invalidates this owner.
/// Consumes self: no typed reads, reuse or second cleanup of the erased owner.
/// No promise of erasing prior compiler copies, registers, paging or core dumps.
pub fn deinit(self: *SecretBytes) void {
    eraseAndFree(self.gpa, self.allocation);
    self.* = undefined;
}

/// Fails before any output. Reflection/field access/exposure can bypass this.
pub fn format(_: *const SecretBytes, _: *std.Io.Writer) error{SecretNotFormattable}!void {
    return error.SecretNotFormattable;
}

fn eraseAndFree(gpa: std.mem.Allocator, allocation: []u8) void {
    std.crypto.secureZero(u8, allocation);
    // Allocator.free poisons memory in Debug before the hook. Use the byte
    // allocation's exact extent/alignment directly so the hook sees zero bytes.
    if (allocation.len != 0) gpa.rawFree(allocation, .fromByteUnits(@alignOf(u8)), @returnAddress());
}
