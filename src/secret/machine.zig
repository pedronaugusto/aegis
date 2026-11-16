//! What a secret computation leaves to the machine: the stack below its caller, and the
//! processor's timing guarantee.
const std = @import("std");
const builtin = @import("builtin");
const registers = @import("registers.zig");

/// Overwrites `bytes` of stack below the caller's frame with zeros: the frames the calls it
/// made used, which hold whatever the compiler spilled or copied there (temporaries no owner
/// names, registers saved across calls, by-value arguments and results). Call it from the frame
/// that ran the secret computation, after it returns (a `defer` there), with at least the depth
/// that computation reaches; `stackReach` measures it. It reaches neither registers still live,
/// nor copies in the caller's own frame, nor a stack a signal handler ran on.
pub noinline fn scrubStack(comptime bytes: usize) void {
    var area: [bytes]u8 = undefined;
    std.crypto.secureZero(u8, &area);
}

/// Erases `bytes` in place, as the owners erase theirs, where no owner can hold them: memory
/// the caller was lent (a scratch buffer its own caller passed in). Memory a caller allocates
/// for a secret is a `SecretBytes` or a `Secret`, which erase it when they end.
pub fn wipe(bytes: []u8) void {
    std.crypto.secureZero(u8, bytes);
}

/// Runs `function(args)` as one secret computation: in a frame of its own, under `Timing`,
/// then `scrubStack(stack_bytes)` from the caller's frame once it returns. `stack_bytes` is at
/// least what `stackReach` measures for the call; a test holding that keeps it so.
pub inline fn scrubbed(comptime stack_bytes: usize, comptime function: anytype, args: anytype) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
    defer scrubStack(stack_bytes);
    const timing = Timing.begin();
    defer timing.end();
    return @call(.never_inline, function, args);
}

/// How many bytes below the caller's frame `function(args)` writes, to choose a `scrubStack`
/// depth with: the window of `bytes` below this frame is painted, the call runs, and the deepest
/// byte it changed is found. Its result is discarded. A call deeper than `bytes` reports `bytes`.
pub noinline fn stackReach(comptime bytes: usize, comptime function: anytype, args: anytype) usize {
    paint(bytes);
    const result = @call(.never_inline, function, args);
    // The measurement is of the stack the call wrote, success or not; the caller runs the call
    // for real elsewhere. The result is kept until here, so the call is not taken away.
    std.mem.doNotOptimizeAway(result);
    const window = registers.stackBelow(bytes);
    for (window, 0..) |byte, i| {
        if (byte != pattern) return bytes - i;
    }
    return 0;
}

const pattern: u8 = 0xa5;

noinline fn paint(comptime bytes: usize) void {
    var area: [bytes + 256]u8 = undefined;
    const volatile_area: *volatile [bytes + 256]u8 = &area;
    for (volatile_area) |*byte| byte.* = pattern;
}

/// Data-independent timing for the span of a secret computation. On AArch64 with FEAT_DIT the
/// architecture then guarantees that data-processing instructions take a time independent of
/// their operands, and Apple's cores from the M3 on turn off the data memory-dependent
/// prefetcher (GoFetch, 2024). Where the processor has no such control it does nothing.
pub const Timing = struct {
    /// Private: the register as `begin` found it, or `untouched` where it set nothing.
    previous: u64,

    /// No DIT register reads this: every bit but the mode's is reserved as zero.
    const untouched = std.math.maxInt(u64);

    const in_target = builtin.cpu.arch == .aarch64 and std.Target.aarch64.featureSetHas(builtin.cpu.features, .dit);

    /// Whether this build can set the processor's data-independent timing mode: an AArch64
    /// target that has FEAT_DIT, or AArch64 Linux, where the kernel says at run time whether the
    /// processor has it (a baseline AArch64 build runs on processors with and without it).
    pub const available = builtin.cpu.arch == .aarch64 and (in_target or builtin.os.tag == .linux);

    /// Whether this processor has the mode: known at compile time where the target has it, asked
    /// of the kernel once otherwise (HWCAP_DIT), since setting it on a processor without it traps.
    pub fn supported() bool {
        if (!available) return false;
        if (in_target) return true;
        return detected();
    }

    /// Turns the mode on; pair with `end` in a `defer`.
    pub inline fn begin() Timing {
        // At compile time first: the AArch64 instructions below must not reach another
        // architecture's assembler, which an unoptimized build would otherwise give them.
        if (comptime !available) return .{ .previous = untouched };
        if (!supported()) return .{ .previous = untouched };
        // DIT's bit 24 is the mode.
        const previous = registers.readDit();
        registers.writeDit(previous | (1 << 24));
        return .{ .previous = previous };
    }

    /// Restores the mode `begin` found. It asks nothing again: `begin` recorded whether it set it.
    pub inline fn end(timing: Timing) void {
        if (comptime !available) return;
        if (timing.previous == untouched) return;
        registers.writeDit(timing.previous);
    }

    /// Whether the mode is on now (false where the processor has none).
    pub fn active() bool {
        if (comptime !available) return false;
        if (!supported()) return false;
        return registers.readDit() & (1 << 24) != 0;
    }

    /// The kernel's answer, asked once per process: 0 not yet asked, 1 absent, 2 present. Racing
    /// first callers ask alike and store alike.
    var detection: std.atomic.Value(u8) = .init(0);

    fn detected() bool {
        switch (detection.load(.monotonic)) {
            1 => return false,
            2 => return true,
            else => {},
        }
        const present = registers.hwcap() & registers.hwcap_dit != 0;
        detection.store(if (present) 2 else 1, .monotonic);
        return present;
    }
};
