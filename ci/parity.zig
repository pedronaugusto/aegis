//! Paired non-elidable consumer/codegen fixtures; compiler flags are recorded in check-parity.
const std = @import("std");
const aegis = @import("aegis");
const cases = @import("cases.zig");
comptime {
    for (.{ [32]u8, [48]u8, cases.Material }) |T| {
        std.debug.assert(@sizeOf(aegis.Secret(T)) == @sizeOf(T));
        std.debug.assert(@alignOf(aegis.Secret(T)) == @alignOf(T));
    }
    for (.{ usize, cases.Counts, cases.Completion }) |T| {
        std.debug.assert(@sizeOf(aegis.Guarded(T)) == @sizeOf(cases.Direct(T)));
        std.debug.assert(@alignOf(aegis.Guarded(T)) == @alignOf(cases.Direct(T)));
        std.debug.assert(@sizeOf(aegis.Guarded(T).Guard) == @sizeOf(*aegis.Guarded(T)));
    }
}
export fn baselineSecretS32(source: *[32]u8) u8 {
    return cases.secret([32]u8, false, source);
}
export fn wrapperSecretS32(source: *[32]u8) u8 {
    return cases.secret([32]u8, true, source);
}
export fn baselineTransferS32(source: *[32]u8, destination: *[32]u8) u8 {
    return cases.transfer([32]u8, false, source, destination);
}
export fn wrapperTransferS32(source: *[32]u8, destination: *[32]u8) u8 {
    return cases.transfer([32]u8, true, source, destination);
}
export fn baselineSecretS48(source: *[48]u8) u8 {
    return cases.secret([48]u8, false, source);
}
export fn wrapperSecretS48(source: *[48]u8) u8 {
    return cases.secret([48]u8, true, source);
}
export fn baselineTransferS48(source: *[48]u8, destination: *[48]u8) u8 {
    return cases.transfer([48]u8, false, source, destination);
}
export fn wrapperTransferS48(source: *[48]u8, destination: *[48]u8) u8 {
    return cases.transfer([48]u8, true, source, destination);
}
export fn baselineSecretMaterial(source: *cases.Material) u8 {
    return cases.secret(cases.Material, false, source);
}
export fn wrapperSecretMaterial(source: *cases.Material) u8 {
    return cases.secret(cases.Material, true, source);
}
export fn baselineTransferMaterial(source: *cases.Material, destination: *cases.Material) u8 {
    return cases.transfer(cases.Material, false, source, destination);
}
export fn wrapperTransferMaterial(source: *cases.Material, destination: *cases.Material) u8 {
    return cases.transfer(cases.Material, true, source, destination);
}
export fn baselineCleanup(fail: bool, seed: u8) u8 {
    return cases.cleanup(false, fail, seed);
}
export fn baselineBudget(owner: *cases.Owner(cases.Counts, false), amount: usize) bool {
    return cases.budget(false, owner, amount);
}
export fn baselineJob(owner: *cases.Owner(cases.Completion, false), value: usize) usize {
    return cases.job(false, owner, value);
}
export fn baselineIncrement(owner: *cases.Owner(usize, false)) void {
    cases.increment(false, owner);
}
export fn wrapperCleanup(fail: bool, seed: u8) u8 {
    return cases.cleanup(true, fail, seed);
}
export fn wrapperBudget(owner: *cases.Owner(cases.Counts, true), amount: usize) bool {
    return cases.budget(true, owner, amount);
}
export fn wrapperJob(owner: *cases.Owner(cases.Completion, true), value: usize) usize {
    return cases.job(true, owner, value);
}
export fn wrapperIncrement(owner: *cases.Owner(usize, true)) void {
    cases.increment(true, owner);
}

export fn baselineCleanupMaterial(fail: bool, seed: u8) u8 {
    return cases.cleanupMaterial(false, fail, seed);
}
export fn wrapperCleanupMaterial(fail: bool, seed: u8) u8 {
    return cases.cleanupMaterial(true, fail, seed);
}

const numeric = @import("numeric.zig");
export fn baselineNumericAdd(x: u64, y: u64) u64 {
    return numeric.operation("add", false, x, y);
}
export fn wrapperNumericAdd(x: u64, y: u64) u64 {
    return numeric.operation("add", true, x, y);
}
export fn baselineNumericSub(x: u64, y: u64) u64 {
    return numeric.operation("sub", false, x, y);
}
export fn wrapperNumericSub(x: u64, y: u64) u64 {
    return numeric.operation("sub", true, x, y);
}
export fn baselineNumericMul(x: u64, y: u64) u64 {
    return numeric.operation("mul", false, x, y);
}
export fn wrapperNumericMul(x: u64, y: u64) u64 {
    return numeric.operation("mul", true, x, y);
}
export fn baselineNumericDiv(x: u64, y: u64) u64 {
    return numeric.operation("div", false, x, y);
}
export fn wrapperNumericDiv(x: u64, y: u64) u64 {
    return numeric.operation("div", true, x, y);
}
export fn baselineNumericRem(x: u64, y: u64) u64 {
    return numeric.operation("rem", false, x, y);
}
export fn wrapperNumericRem(x: u64, y: u64) u64 {
    return numeric.operation("rem", true, x, y);
}
export fn baselineNumericShift(x: u64, y: u64) u64 {
    return numeric.operation("shift", false, x, y);
}
export fn wrapperNumericShift(x: u64, y: u64) u64 {
    return numeric.operation("shift", true, x, y);
}
export fn baselineNumericSaturating(x: u64, y: u64) u64 {
    return numeric.operation("saturating", false, x, y);
}
export fn wrapperNumericSaturating(x: u64, y: u64) u64 {
    return numeric.operation("saturating", true, x, y);
}
export fn baselineNumericRanged(x: u64, y: u64) u64 {
    return numeric.operation("ranged", false, x, y);
}
export fn wrapperNumericRanged(x: u64, y: u64) u64 {
    return numeric.operation("ranged", true, x, y);
}
export fn baselineNumericCast(x: u64, y: u64) u64 {
    return numeric.operation("cast", false, x, y);
}
export fn wrapperNumericCast(x: u64, y: u64) u64 {
    return numeric.operation("cast", true, x, y);
}
export fn baselineNumericIdentity(x: u64, y: u64) u64 {
    return numeric.operation("identity", false, x, y);
}
export fn wrapperNumericIdentity(x: u64, y: u64) u64 {
    return numeric.operation("identity", true, x, y);
}
export fn baselineNumericCounter(x: u64, y: u64) u64 {
    return numeric.operation("counter", false, x, y);
}
export fn wrapperNumericCounter(x: u64, y: u64) u64 {
    return numeric.operation("counter", true, x, y);
}
export fn baselineNumericCount(x: u64, y: u64) u64 {
    return numeric.operation("count", false, x, y);
}
export fn wrapperNumericCount(x: u64, y: u64) u64 {
    return numeric.operation("count", true, x, y);
}
export fn baselineNumericBits(x: u64, y: u64) u64 {
    return numeric.operation("bits", false, x, y);
}
export fn wrapperNumericBits(x: u64, y: u64) u64 {
    return numeric.operation("bits", true, x, y);
}
export fn baselineNumericDuration(x: u64, y: u64) u64 {
    return numeric.operation("duration", false, x, y);
}
export fn wrapperNumericDuration(x: u64, y: u64) u64 {
    return numeric.operation("duration", true, x, y);
}
export fn baselineNumericRounding(x: u64, y: u64) u64 {
    return numeric.operation("rounding", false, x, y);
}
export fn wrapperNumericRounding(x: u64, y: u64) u64 {
    return numeric.operation("rounding", true, x, y);
}
export fn baselineNumericInstant(x: u64, y: u64) u64 {
    return numeric.operation("instant", false, x, y);
}
export fn wrapperNumericInstant(x: u64, y: u64) u64 {
    return numeric.operation("instant", true, x, y);
}
export fn baselineNumericInvariant(x: u64, y: u64) u64 {
    return numeric.operation("invariant", false, x, y);
}
export fn wrapperNumericInvariant(x: u64, y: u64) u64 {
    return numeric.operation("invariant", true, x, y);
}
export fn baselineNumericDiagnostics(x: u64, y: u64) u64 {
    return numeric.operation("diagnostics", false, x, y);
}
export fn wrapperNumericDiagnostics(x: u64, y: u64) u64 {
    return numeric.operation("diagnostics", true, x, y);
}
export fn baselineNumericEncoding(x: u64, y: u64) u64 {
    return numeric.operation("encoding", false, x, y);
}
export fn wrapperNumericEncoding(x: u64, y: u64) u64 {
    return numeric.operation("encoding", true, x, y);
}

const bytes = @import("bytes.zig");
comptime {
    std.debug.assert(@sizeOf(aegis.SecretBytes) == @sizeOf(bytes.Direct));
    std.debug.assert(@alignOf(aegis.SecretBytes) == @alignOf(bytes.Direct));
}
export fn baselineBytesDead(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("dead", false, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn wrapperBytesDead(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("dead", true, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn baselineBytesCleanup(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("cleanup", false, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn wrapperBytesCleanup(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("cleanup", true, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn baselineBytesResize(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("resize", false, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn wrapperBytesResize(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("resize", true, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn baselineBytesReserve(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("reserve", false, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn wrapperBytesReserve(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, requested: usize, fail: bool) usize {
    return bytes.consumer("reserve", true, gpa.*, input[0..n], capacity, requested, fail) catch 0;
}
export fn baselineBytesMove(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, fail: bool) usize {
    return bytes.moveConsumer(false, gpa.*, input[0..n], capacity, fail) catch 0;
}
export fn wrapperBytesMove(gpa: *const std.mem.Allocator, input: [*]const u8, n: usize, capacity: usize, fail: bool) usize {
    return bytes.moveConsumer(true, gpa.*, input[0..n], capacity, fail) catch 0;
}
export fn baselineBytesAdoptDead(gpa: *const std.mem.Allocator, allocation: [*]u8, capacity: usize, live_len: usize) void {
    bytes.adoptDead(false, gpa.*, allocation[0..capacity], live_len);
}
export fn baselineBytesReplace(gpa: *const std.mem.Allocator, allocation: [*]u8, capacity: usize, live_len: usize, input: [*]const u8, n: usize) usize {
    return bytes.replaceConsumer(false, gpa.*, allocation[0..capacity], live_len, input[0..n]) catch 0;
}
export fn wrapperBytesAdoptDead(gpa: *const std.mem.Allocator, allocation: [*]u8, capacity: usize, live_len: usize) void {
    bytes.adoptDead(true, gpa.*, allocation[0..capacity], live_len);
}
export fn wrapperBytesReplace(gpa: *const std.mem.Allocator, allocation: [*]u8, capacity: usize, live_len: usize, input: [*]const u8, n: usize) usize {
    return bytes.replaceConsumer(true, gpa.*, allocation[0..capacity], live_len, input[0..n]) catch 0;
}
