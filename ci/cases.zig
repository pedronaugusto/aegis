//! Equivalent hand-written baselines: same volatile erasure and acquire/release ordering.
const std = @import("std");
const aegis = @import("aegis");
pub const Material = @import("material").Material;
pub const Counts = struct { jobs: usize = 0, bytes: usize = 0 };
pub const Completion = struct { phase: enum { pending, ready, acknowledged } = .pending, result: ?usize = null };
pub fn Direct(comptime T: type) type {
    return struct { lock: std.atomic.Value(bool) = .init(false), data: T };
}
pub fn Owner(comptime T: type, comptime wrapped: bool) type {
    return if (wrapped) aegis.Guarded(T) else Direct(T);
}
fn lock(comptime T: type, owner: *Direct(T)) void {
    while (owner.lock.swap(true, .acquire)) {
        while (owner.lock.load(.monotonic)) std.atomic.spinLoopHint();
    }
}

pub fn secret(comptime T: type, comptime wrapped: bool, source: *T) u8 {
    std.mem.doNotOptimizeAway(source);
    if (wrapped) {
        // safe: Secret(T) has exactly T's size/alignment and sole inline field, checked in parity.zig
        const owner: *aegis.Secret(T) = @ptrCast(source); // safe: identical inline T layout, checked by parity.zig
        defer owner.deinit();
        return use(T, owner.expose());
    } else {
        defer std.crypto.secureZero(u8, std.mem.asBytes(source));
        return use(T, source);
    }
}

fn use(comptime T: type, source: *const T) u8 {
    if (T == Material) return source.rsa.n[0] ^ source.rsa.d[0];
    return source[0] ^ source[source.len - 1];
}

pub fn transfer(comptime T: type, comptime wrapped: bool, source: *T, destination: *T) u8 {
    @setRuntimeSafety(true);
    std.mem.doNotOptimizeAway(source);
    if (wrapped) {
        // safe: both pointers reference disjoint fixed T storage, with verified identical owner layout
        const owner: *aegis.Secret(T) = @ptrCast(source); // safe: identical inline T layout, checked by parity.zig
        // safe: destination is uninitialized T storage with Secret(T)'s identical alignment and size
        const next: *aegis.Secret(T) = @ptrCast(destination); // safe: disjoint uninitialized storage with identical T layout
        owner.moveInto(next);
        std.mem.doNotOptimizeAway(destination);
        defer next.deinit();
        return use(T, next.expose());
    } else {
        @memcpy(std.mem.asBytes(destination), std.mem.asBytes(source));
        std.crypto.secureZero(u8, std.mem.asBytes(source));
        std.mem.doNotOptimizeAway(destination);
        defer std.crypto.secureZero(u8, std.mem.asBytes(destination));
        return use(T, destination);
    }
}

pub fn cleanup(comptime wrapped: bool, fail: bool, seed: u8) u8 {
    // A PrivateKey-like caller: both normal and public failure paths have dead final storage.
    if (wrapped) {
        var source = aegis.Secret([48]u8).init(@splat(seed));
        defer source.deinit();
        if (fail) return 1;
        return source.expose()[0];
    } else {
        var source: [48]u8 = @splat(seed);
        defer std.crypto.secureZero(u8, &source);
        if (fail) return 1;
        return source[0];
    }
}

fn DirectSecret(comptime T: type) type {
    return struct {
        const Self = @This();
        material: T,
        fn init(value: T) Self {
            return .{ .material = value };
        }
    };
}

pub fn cleanupMaterial(comptime wrapped: bool, fail: bool, seed: u8) u8 {
    if (wrapped) {
        var owner = aegis.Secret(Material).init(.{ .rsa = .{ .size = 256, .exponent_size = 3, .n = @splat(seed), .d = @splat(seed) } });
        defer owner.deinit();
        if (fail) return 1;
        return owner.expose().rsa.d[0];
    } else {
        var owner = DirectSecret(Material).init(.{ .rsa = .{ .size = 256, .exponent_size = 3, .n = @splat(seed), .d = @splat(seed) } });
        defer std.crypto.secureZero(u8, std.mem.asBytes(&owner.material));
        if (fail) return 1;
        return owner.material.rsa.d[0];
    }
}

pub fn budget(comptime wrapped: bool, owner: *Owner(Counts, wrapped), amount: usize) bool {
    @setRuntimeSafety(true);
    if (wrapped) {
        {
            var held = owner.acquire();
            defer held.deinit();
            if (!charge(held.value(), amount)) return false;
        }
        var held = owner.acquire();
        defer held.deinit();
        uncharge(held.value(), amount);
    } else {
        {
            lock(Counts, owner);
            defer owner.lock.store(false, .release);
            if (!charge(&owner.data, amount)) return false;
        }
        lock(Counts, owner);
        defer owner.lock.store(false, .release);
        uncharge(&owner.data, amount);
    }
    return true;
}
fn charge(active: *Counts, amount: usize) bool {
    @setRuntimeSafety(true);
    std.mem.doNotOptimizeAway(active);
    const max_bytes = 16 * 1024 * 1024;
    if (active.jobs >= 64 or active.bytes > max_bytes or amount > max_bytes -| active.bytes) return false;
    active.jobs += 1;
    active.bytes += amount;
    std.mem.doNotOptimizeAway(active);
    return true;
}
fn uncharge(active: *Counts, amount: usize) void {
    @setRuntimeSafety(true);
    if (active.bytes < amount or active.jobs == 0) @panic("admission released without ownership");
    active.jobs -= 1;
    active.bytes -= amount;
    std.mem.doNotOptimizeAway(active);
}

pub fn job(comptime wrapped: bool, owner: *Owner(Completion, wrapped), value: usize) usize {
    @setRuntimeSafety(true);
    if (wrapped) {
        {
            var held = owner.acquire();
            defer held.deinit();
            held.value().result = value;
            held.value().phase = .ready;
            std.mem.doNotOptimizeAway(held.value());
        }
        var held = owner.acquire();
        defer held.deinit();
        const result = held.value().result.?;
        held.value().result = null;
        held.value().phase = .acknowledged;
        std.mem.doNotOptimizeAway(held.value());
        return result;
    } else {
        lock(Completion, owner);
        owner.data.result = value;
        owner.data.phase = .ready;
        std.mem.doNotOptimizeAway(&owner.data);
        owner.lock.store(false, .release);
        lock(Completion, owner);
        defer owner.lock.store(false, .release);
        const result = owner.data.result.?;
        owner.data.result = null;
        owner.data.phase = .acknowledged;
        std.mem.doNotOptimizeAway(&owner.data);
        return result;
    }
}

pub fn increment(comptime wrapped: bool, owner: *Owner(usize, wrapped)) void {
    if (wrapped) {
        var held = owner.acquire();
        defer held.deinit();
        held.value().* +%= 1;
    } else {
        lock(usize, owner);
        defer owner.lock.store(false, .release);
        owner.data +%= 1;
    }
}
