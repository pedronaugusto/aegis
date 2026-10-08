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
