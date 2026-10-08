//! Equivalent handwritten FULL-capacity owner for enclosing release-cost fixtures.
//! Not a rival adapter; erasure, checks, transfer and allocation policy match.
const std = @import("std");
const aegis = @import("aegis");

pub const Direct = struct {
    gpa: std.mem.Allocator,
    allocation: []u8,
    used_len: usize,
    pub fn init(gpa: std.mem.Allocator, full_capacity: usize) !Direct {
        const memory = try gpa.alloc(u8, full_capacity);
        @memset(memory, 0);
        return .{ .gpa = gpa, .allocation = memory, .used_len = 0 };
    }
    pub fn adopt(gpa: std.mem.Allocator, memory: []u8, n: usize) !Direct {
        if (n > memory.len) return error.InvalidLength;
        return .{ .gpa = gpa, .allocation = memory, .used_len = n };
    }
    pub fn len(self: *const Direct) usize {
        return self.used_len;
    }
    pub fn capacity(self: *const Direct) usize {
        return self.allocation.len;
    }
    pub fn expose(self: *const Direct) []const u8 {
        return self.allocation[0..self.used_len];
    }
    pub fn exposeMut(self: *Direct) []u8 {
        return self.allocation[0..self.used_len];
    }
    pub fn resizeWithinCapacity(self: *Direct, n: usize) !void {
        if (n > self.allocation.len) return error.CapacityExceeded;
        if (n < self.used_len) {
            std.crypto.secureZero(u8, self.allocation[n..self.used_len]);
        } else {
            @memset(self.allocation[self.used_len..n], 0);
        }
        self.used_len = n;
    }
    pub fn replace(self: *Direct, source: []const u8) !void {
        if (source.len > self.allocation.len) return error.CapacityExceeded;
        if (source.len != 0 and self.allocation.len != 0) {
            const x = @intFromPtr(self.allocation.ptr); // safe: numerical address comparison only, no dereference
            const y = @intFromPtr(source.ptr); // safe: valid input slice address, compared without dereferencing
            if (if (x <= y) y - x < self.allocation.len else x - y < source.len) return error.Overlap;
        }
        std.crypto.secureZero(u8, self.allocation[0..self.used_len]);
        @memcpy(self.allocation[0..source.len], source);
        self.used_len = source.len;
    }
    pub fn reserve(self: *Direct, n: usize) !void {
        if (n <= self.allocation.len) return;
        const next = try self.gpa.alloc(u8, n);
        @memset(next, 0);
        @memcpy(next[0..self.used_len], self.allocation[0..self.used_len]);
        wipeFree(self.gpa, self.allocation);
        self.allocation = next;
    }
    pub fn moveInto(self: *Direct, destination: *Direct) void {
        @setRuntimeSafety(true);
        @memcpy(std.mem.asBytes(destination), std.mem.asBytes(self));
        std.crypto.secureZero(u8, std.mem.asBytes(self));
    }
    pub fn deinit(self: *Direct) void {
        wipeFree(self.gpa, self.allocation);
        self.* = undefined;
    }
};
fn wipeFree(gpa: std.mem.Allocator, memory: []u8) void {
    std.crypto.secureZero(u8, memory);
    if (memory.len != 0) gpa.rawFree(memory, .fromByteUnits(@alignOf(u8)), @returnAddress());
}
pub fn Owner(comptime wrapped: bool) type {
    return if (wrapped) aegis.SecretBytes else Direct;
}

// A PEM/DER-style decode/parser and KDF temporary all stay within aegis.
// Public input and runtime capacity prevent a constant-size-only proof.
pub fn consumer(comptime name: []const u8, comptime wrapped: bool, gpa: std.mem.Allocator, input: []const u8, full_capacity: usize, requested: usize, fail: bool) !usize {
    var owner = try Owner(wrapped).init(gpa, full_capacity);
    defer owner.deinit();
    try owner.replace(input);
    if (comptime std.mem.eql(u8, name, "dead")) {
        // Last use has no observable bytes: allocator free still follows volatile
        // full-capacity wipe, including slack. No artificial read-after-wipe.
        return 0;
    }
    if (fail) return error.InvalidKey;
    if (comptime std.mem.eql(u8, name, "resize")) {
        try owner.resizeWithinCapacity(requested);
    } else if (comptime std.mem.eql(u8, name, "reserve")) {
        try owner.reserve(requested);
    }
    const bytes = owner.expose();
    return owner.capacity() +% owner.len() +% (if (bytes.len == 0) @as(usize, 0) else bytes[0]);
}

pub fn moveConsumer(comptime wrapped: bool, gpa: std.mem.Allocator, input: []const u8, capacity: usize, fail: bool) !usize {
    var owner = try Owner(wrapped).init(gpa, capacity);
    errdefer owner.deinit();
    try owner.replace(input);
    if (fail) return error.InvalidKey;
    var destination: Owner(wrapped) = undefined;
    owner.moveInto(&destination);
    defer destination.deinit();
    return destination.capacity() +% destination.len();
}

pub fn adoptDead(comptime wrapped: bool, gpa: std.mem.Allocator, allocation: []u8, live_len: usize) void {
    var owner = Owner(wrapped).adopt(gpa, allocation, live_len) catch return;
    owner.deinit();
}
pub fn replaceConsumer(comptime wrapped: bool, gpa: std.mem.Allocator, allocation: []u8, live_len: usize, input: []const u8) !usize {
    var owner = try Owner(wrapped).adopt(gpa, allocation, live_len);
    defer owner.deinit();
    try owner.replace(input);
    return owner.len();
}
