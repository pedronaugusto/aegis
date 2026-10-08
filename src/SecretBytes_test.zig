const std = @import("std");
const shake = @import("shakedown");
const SecretBytes = @import("SecretBytes.zig");

// Inspects while the allocation is still valid, BEFORE forwarding free. Never
// reads freed memory, formats content, or relies on Debug allocator poisoning.
const Observer = struct {
    child: std.mem.Allocator,
    allocations: usize = 0,
    frees: usize = 0,
    bytes_freed: usize = 0,
    live: usize = 0,
    resize_calls: usize = 0,
    remap_calls: usize = 0,
    fail: bool = false,

    fn allocator(self: *Observer) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .free = free, .resize = resize, .remap = remap } };
    }
    fn of(ptr: *anyopaque) *Observer {
        return @ptrCast(@alignCast(ptr)); // safe: only paired with *Observer by allocator()
    }
    fn alloc(ptr: *anyopaque, n: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self = of(ptr);
        if (self.fail) return null;
        const memory = self.child.rawAlloc(n, alignment, ret) orelse return null;
        self.allocations += 1;
        self.live += 1;
        @memset(memory[0..n], 0xd7);
        return memory;
    }
    fn free(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self = of(ptr);
        // All-build regression: neither std assert nor an expected secret dump.
        for (memory) |byte| if (byte != 0) @panic("secret allocation freed before complete erasure");
        self.frees += 1;
        self.bytes_freed += memory.len;
        self.live -= 1;
        self.child.rawFree(memory, alignment, ret);
    }
    fn resize(ptr: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        of(ptr).resize_calls += 1;
        return false;
    }
    fn remap(ptr: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        of(ptr).remap_calls += 1;
        return null;
    }
};
fn zero(bytes: []const u8) !void {
    for (bytes) |byte| try std.testing.expect(byte == 0);
}
fn quietEqual(a: []const u8, b: []const u8) !void {
    try std.testing.expect(std.mem.eql(u8, a, b));
}

test "A4 SecretBytes init zeros entire capacity and exposes only live bytes" {
    var observe: Observer = .{ .child = std.testing.allocator };
    var owner = try SecretBytes.init(observe.allocator(), 64);
    try std.testing.expectEqual(@as(usize, 0), owner.len());
    try std.testing.expectEqual(@as(usize, 64), owner.capacity());
    try std.testing.expectEqual(@as(usize, 0), owner.expose().len);
    try std.testing.expectEqual(@as(usize, 0), owner.exposeMut().len);
    try zero(owner.allocation);
    try owner.resizeWithinCapacity(8);
    @memset(owner.exposeMut(), 0x5b);
    owner.deinit();
    try std.testing.expectEqual(@as(usize, 1), observe.frees);
    try std.testing.expectEqual(@as(usize, 64), observe.bytes_freed);
    try std.testing.expectEqual(@as(usize, 0), observe.live);
}

test "A4 SecretBytes adopt ownership failure and nonzero or undefined slack" {
    var observe: Observer = .{ .child = std.testing.allocator };
    const gpa = observe.allocator();
    const allocation = try gpa.alloc(u8, 48);
    @memset(allocation, 0xb3);
    try std.testing.expectError(error.InvalidLength, SecretBytes.adopt(gpa, allocation, 49));
    try std.testing.expectEqual(@as(usize, 0), observe.frees);
    for (allocation) |byte| try std.testing.expect(byte == 0xb3);
    var owner = try SecretBytes.adopt(gpa, allocation, 4);
    try std.testing.expect(owner.expose().ptr == allocation.ptr);
    try std.testing.expectEqual(@as(usize, 4), owner.expose().len);
    owner.deinit();
    try std.testing.expectEqual(@as(usize, 48), observe.bytes_freed);
    const undefined_slack = try gpa.alloc(u8, 32);
    @memset(undefined_slack, undefined);
    undefined_slack[0] = 0x77;
    var other = try SecretBytes.adopt(gpa, undefined_slack, 1);
    other.deinit(); // never reads slack before secure erasure
    try std.testing.expectEqual(@as(usize, 0), observe.live);
}

test "A4 SecretBytes shrink erases tail immediately and grow zeros newly live bytes" {
    var observe: Observer = .{ .child = std.testing.allocator };
    const allocation = try observe.allocator().alloc(u8, 64);
    @memset(allocation, 0x51);
    var owner = try SecretBytes.adopt(observe.allocator(), allocation, 32);
    defer owner.deinit();
    const borrow = owner.expose();
    try std.testing.expectError(error.CapacityExceeded, owner.resizeWithinCapacity(65));
    try std.testing.expect(owner.expose().ptr == borrow.ptr and owner.len() == 32);
    for (allocation) |byte| try std.testing.expect(byte == 0x51);
    try owner.resizeWithinCapacity(3);
    try zero(allocation[3..32]);
    for (allocation[32..]) |byte| try std.testing.expect(byte == 0x51);
    try owner.resizeWithinCapacity(60);
    try zero(owner.expose()[3..]);
    try owner.resizeWithinCapacity(0);
    try zero(allocation[0..60]);
    try owner.resizeWithinCapacity(64);
    try zero(owner.expose());
}

test "A4 SecretBytes replace rejects live and slack overlap before mutation" {
    var observe: Observer = .{ .child = std.testing.allocator };
    const allocation = try observe.allocator().alloc(u8, 32);
    @memset(allocation, 0x6b);
    var owner = try SecretBytes.adopt(observe.allocator(), allocation, 16);
    defer owner.deinit();
    const borrow = owner.expose();
    for ([_][]const u8{ allocation[0..16], allocation[7..20], allocation[16..24], allocation[31..] }) |input| {
        try std.testing.expectError(error.Overlap, owner.replace(input));
        try std.testing.expect(owner.len() == 16 and owner.expose().ptr == borrow.ptr);
        for (allocation) |byte| try std.testing.expect(byte == 0x6b);
    }
    try std.testing.expectError(error.CapacityExceeded, owner.replace(&(@as([33]u8, @splat(0x24)))));
    try owner.replace("xyz");
    try quietEqual(owner.expose(), "xyz");
    try zero(allocation[3..16]);
    for (allocation[16..]) |byte| try std.testing.expect(byte == 0x6b);
    try owner.replace(allocation[32..]); // zero occupied bytes cannot overlap
    try std.testing.expectEqual(@as(usize, 0), owner.len());
    try zero(allocation[0..16]);
}

test "A4 SecretBytes overlap input before backing start and boundary adjacency" {
    // FixedBufferAllocator's full owned suballocation sits within a known array;
    // enclosing borrowed inputs are valid slices and expose both overlap orders.
    var storage: [128]u8 = @splat(0x57);
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    _ = try fixed.allocator().alloc(u8, 16);
    var owner = try SecretBytes.init(fixed.allocator(), 32);
    defer owner.deinit();
    try owner.resizeWithinCapacity(8);
    @memset(owner.exposeMut(), 0x68);
    try std.testing.expectError(error.Overlap, owner.replace(storage[8..24]));
    try std.testing.expectError(error.Overlap, owner.replace(storage[32..56]));
    try owner.replace(storage[0..16]); // exactly adjacent before allocation
    try owner.replace(storage[48..64]); // exactly adjacent after allocation
    for (owner.expose()) |byte| try std.testing.expect(byte == 0x57);
}

test "A4 SecretBytes reserve OOM preserves ownership and borrows without remap" {
    var observe: Observer = .{ .child = std.testing.allocator };
    var owner = try SecretBytes.init(observe.allocator(), 16);
    try owner.replace("payload");
    @memset(owner.allocation[owner.len()..], 0xa1);
    const borrow = owner.expose();
    observe.fail = true;
    try std.testing.expectError(error.OutOfMemory, owner.reserve(80));
    try std.testing.expect(owner.expose().ptr == borrow.ptr and owner.capacity() == 16);
    try quietEqual(borrow, "payload");
    try std.testing.expectEqual(@as(usize, 0), observe.frees);
    try owner.reserve(0);
    try owner.reserve(16);
    try std.testing.expect(owner.expose().ptr == borrow.ptr);
    observe.fail = false;
    try owner.reserve(80);
    // Do not dereference old borrow after successful reserve.
    try std.testing.expectEqual(@as(usize, 80), owner.capacity());
    try quietEqual(owner.expose(), "payload");
    try zero(owner.allocation[owner.len()..]);
    try std.testing.expectEqual(@as(usize, 1), observe.frees);
    try std.testing.expectEqual(@as(usize, 16), observe.bytes_freed);
    try std.testing.expectEqual(@as(usize, 0), observe.resize_calls + observe.remap_calls);
    owner.deinit();
    try std.testing.expectEqual(@as(usize, 2), observe.allocations);
    try std.testing.expectEqual(@as(usize, 96), observe.bytes_freed);
    try std.testing.expectEqual(@as(usize, 0), observe.live);
}

test "A4 SecretBytes explicit move preserves full owner and erases source descriptor" {
    var observe: Observer = .{ .child = std.testing.allocator };
    var owner = try SecretBytes.init(observe.allocator(), 48);
    try owner.replace("key");
    @memset(owner.allocation[3..], 0x93);
    const address = owner.expose().ptr;
    var destination: SecretBytes = undefined;
    owner.moveInto(&destination);
    try zero(std.mem.asBytes(&owner));
    try std.testing.expect(destination.expose().ptr == address and destination.capacity() == 48);
    try quietEqual(destination.expose(), "key");
    try std.testing.expectEqual(@as(usize, 0), observe.frees);
    destination.deinit();
    try std.testing.expectEqual(@as(usize, 48), observe.bytes_freed);
    try std.testing.expectEqual(@as(usize, 0), observe.live);
}

test "A4 SecretBytes zero capacity empty adoption and fail-closed formatting" {
    var observe: Observer = .{ .child = std.testing.allocator };
    var owner = try SecretBytes.init(observe.allocator(), 0);
    try owner.resizeWithinCapacity(0);
    try owner.replace(&.{});
    try owner.reserve(0);
    var output: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try std.testing.expectError(error.SecretNotFormattable, owner.format(&writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
    try std.testing.expectError(error.CapacityExceeded, owner.resizeWithinCapacity(1));
    try std.testing.expectError(error.CapacityExceeded, owner.replace("a"));
    owner.deinit();
    var adopted = try SecretBytes.adopt(observe.allocator(), &.{}, 0);
    adopted.deinit();
    try std.testing.expectEqual(@as(usize, 0), observe.allocations + observe.frees);
    var populated = try SecretBytes.init(observe.allocator(), 8);
    try populated.replace("hidden");
    try std.testing.expectError(error.SecretNotFormattable, populated.format(&writer));
    try std.testing.expectEqual(@as(usize, 0), writer.end);
    populated.deinit();
}

fn allocationFailures(gpa: std.mem.Allocator) !void {
    var observe: Observer = .{ .child = gpa };
    var owner = try SecretBytes.init(observe.allocator(), 32);
    defer owner.deinit();
    try owner.replace("private-material");
    @memset(owner.allocation[owner.len()..], 0x9b);
    const borrow = owner.expose();
    owner.reserve(96) catch |err| {
        try std.testing.expect(owner.expose().ptr == borrow.ptr and owner.capacity() == 32);
        try quietEqual(borrow, "private-material");
        return err;
    };
    try zero(owner.allocation[owner.len()..]);
    try quietEqual(owner.expose(), "private-material");
    const retained = owner.expose();
    owner.reserve(192) catch |err| {
        try std.testing.expect(owner.expose().ptr == retained.ptr and owner.capacity() == 96);
        try quietEqual(retained, "private-material");
        return err;
    };
    try std.testing.expectEqual(@as(usize, 0), observe.resize_calls + observe.remap_calls);
}
test "A4 SecretBytes every allocation failure on NoResize cleans full capacity" {
    var no_resize = shake.alloc.NoResize.init(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), allocationFailures, .{});
}

fn parseFixture(gpa: std.mem.Allocator, fail_parse: bool, fail_later: bool) !SecretBytes {
    // Cloak-like PEM/DER decode plus final key-owner allocation stays in aegis.
    var observe_owner = try SecretBytes.init(gpa, 96);
    errdefer observe_owner.deinit();
    try observe_owner.replace("decoded-key-material");
    if (fail_parse) return error.InvalidKey;
    try observe_owner.resizeWithinCapacity(12);
    try observe_owner.reserve(160);
    if (fail_later) return error.LateFailure;
    var result: SecretBytes = undefined;
    observe_owner.moveInto(&result);
    return result; // explicit moved owner, never a bare slice
}
test "A4 Consumer Key PEM DER KDF success and error defers wipe all slack" {
    var observe: Observer = .{ .child = std.testing.allocator };
    try std.testing.expectError(error.InvalidKey, parseFixture(observe.allocator(), true, false));
    try std.testing.expectError(error.LateFailure, parseFixture(observe.allocator(), false, true));
    var key = try parseFixture(observe.allocator(), false, false);
    // KDF-style explicitly scoped scratch, caller's passphrase is only borrowed.
    var scratch = try SecretBytes.init(observe.allocator(), 48);
    try scratch.replace("borrowed-passphrase");
    scratch.deinit();
    key.deinit();
    try std.testing.expectEqual(@as(usize, 0), observe.live);
    try std.testing.expectEqual(observe.allocations, observe.frees);
}

fn resizeProperty(_: void, c: *shake.Case) !void {
    const cap = shake.gen.intRange(c.source, usize, 0, 64);
    var observe: Observer = .{ .child = std.testing.allocator };
    var owner = try SecretBytes.init(observe.allocator(), cap);
    defer owner.deinit();
    var oracle: [64]u8 = @splat(0);
    var live: usize = 0;
    for (0..48) |_| {
        const next = shake.gen.intRange(c.source, usize, 0, 80);
        if (next > cap) {
            try std.testing.expectError(error.CapacityExceeded, owner.resizeWithinCapacity(next));
        } else {
            // Independent per-index live-set oracle: every membership change
            // loses its old value; unaffected indices retain theirs.
            for (oracle[0..cap], 0..) |*byte, i| {
                if ((i < live) != (i < next)) byte.* = 0;
            }
            try owner.resizeWithinCapacity(next);
            live = next;
        }
        try std.testing.expect(owner.len() == live and owner.capacity() == cap);
        try quietEqual(owner.allocation, oracle[0..cap]);
        const public_pattern = shake.gen.int(c.source, u8);
        @memset(owner.exposeMut(), public_pattern);
        @memset(oracle[0..live], public_pattern);
    }
}
test "A4 SecretBytes shakedown shrinking resize traces preserve independent live-set oracle" {
    try shake.check(std.testing.allocator, {}, resizeProperty, .{ .cases = 128 });
}
