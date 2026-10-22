//! Necessary handwritten operations paired with the modules A11 brought under the gate: the
//! reader-writer spin guard, the data-independent timing span and the stack scrub.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("aegis");

/// The hand-written reader-writer spin lock: a reader count, a waiting-writer bit and a
/// writing bit in one word, beside the data.
pub const DirectSpinRw = struct { state: std.atomic.Value(u32) = .init(0), data: u64 };
const writing: u32 = 1 << 31;
const waiting: u32 = 1 << 30;
const readers: u32 = waiting - 1;

pub fn spinRead(comptime wrapped: bool, owner: if (wrapped) *a.SpinRwGuarded(u64) else *DirectSpinRw) u64 {
    if (wrapped) {
        var held = owner.read();
        defer held.deinit();
        return held.value().*;
    }
    while (true) {
        if (directTryRead(owner)) break;
        while (owner.state.load(.monotonic) & (writing | waiting) != 0) std.atomic.spinLoopHint();
    }
    defer {
        const before = owner.state.fetchSub(1, .release);
        std.debug.assert(before & readers != 0);
    }
    return owner.data;
}

fn directTryRead(owner: *DirectSpinRw) bool {
    var current = owner.state.load(.monotonic);
    while (current & (writing | waiting) == 0) {
        std.debug.assert(current & readers != readers);
        current = owner.state.cmpxchgWeak(current, current + 1, .acquire, .monotonic) orelse return true;
    }
    return false;
}

pub fn spinWrite(comptime wrapped: bool, owner: if (wrapped) *a.SpinRwGuarded(u64) else *DirectSpinRw, value: u64) void {
    if (wrapped) {
        var held = owner.write();
        defer held.deinit();
        held.value().* +%= value;
        return;
    }
    while (true) {
        var current = owner.state.load(.monotonic);
        if (current & (writing | readers) == 0) {
            current = owner.state.cmpxchgWeak(current, (current & ~waiting) | writing, .acquire, .monotonic) orelse break;
            continue;
        }
        if (current & waiting == 0) _ = owner.state.fetchOr(waiting, .monotonic);
        std.atomic.spinLoopHint();
    }
    defer {
        const before = owner.state.fetchAnd(~writing, .release);
        std.debug.assert(before & writing != 0);
    }
    owner.data +%= value;
}

/// Sets data-independent timing around the work where the processor has the mode, as a
/// careful caller would by hand: known from the target, or asked of the kernel once on
/// AArch64 Linux, and the register as found kept for the end, which may be elsewhere, with a
/// value no DIT register reads standing for "set nothing". Elsewhere the span is nothing.
pub fn timingSpan(comptime wrapped: bool, value: *const [32]u8) u8 {
    if (wrapped) {
        const timing = a.secret.Timing.begin();
        defer timing.end();
        return fold(value);
    }
    const available = builtin.cpu.arch == .aarch64 and (direct_in_target or builtin.os.tag == .linux);
    if (comptime !available) return fold(value);
    const untouched = std.math.maxInt(u64);
    var previous: u64 = untouched;
    if (directSupported()) {
        previous = asm volatile ("mrs %[value], s3_3_c4_c2_5"
            : [value] "=r" (-> u64),
        );
        asm volatile ("msr s3_3_c4_c2_5, %[value]"
            :
            : [value] "r" (previous | (1 << 24)),
            : .{ .memory = true });
    }
    defer if (previous != untouched) asm volatile ("msr s3_3_c4_c2_5, %[value]"
        :
        : [value] "r" (previous),
        : .{ .memory = true });
    return fold(value);
}

/// The work under the span: every byte read, so neither side can drop it.
fn fold(value: *const [32]u8) u8 {
    var sum: u8 = 0;
    for (value) |byte| sum +%= byte;
    return sum;
}

const direct_in_target = builtin.cpu.arch == .aarch64 and std.Target.aarch64.featureSetHas(builtin.cpu.features, .dit);
var direct_detection: std.atomic.Value(u8) = .init(0);

fn directSupported() bool {
    if (direct_in_target) return true;
    switch (direct_detection.load(.monotonic)) {
        1 => return false,
        2 => return true,
        else => {},
    }
    const hwcap = if (builtin.link_libc) std.c.getauxval(std.elf.AT.HWCAP) else std.os.linux.getauxval(std.elf.AT.HWCAP);
    const present = hwcap & std.os.linux.HWCAP.DIT != 0;
    direct_detection.store(if (present) 2 else 1, .monotonic);
    return present;
}

/// A frame of zeros below the caller, written by volatile stores the optimizer keeps.
pub fn scrub(comptime wrapped: bool) void {
    if (wrapped) return a.secret.scrubStack(256);
    directScrub(256);
}

noinline fn directScrub(comptime bytes: usize) void {
    var area: [bytes]u8 = undefined;
    std.crypto.secureZero(u8, &area);
}
