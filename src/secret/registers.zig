//! What a secret computation asks of the machine below the language: the processor's timing
//! register, the kernel's hardware capabilities, the stack below a frame, and a value the
//! optimizer cannot see through. glint's P007 seam for them (glint.json), and nothing else lives
//! here. Each names what it needs at its declaration.
const std = @import("std");
const builtin = @import("builtin");

/// AArch64's DIT register (S3_3_C4_C2_5), spelled as the register number so no assembler feature
/// is needed beyond what the target already has: a processor with FEAT_DIT, which the caller
/// established (setting it on one without traps). Only an AArch64 build reaches it.
pub inline fn readDit() u64 {
    comptime std.debug.assert(builtin.cpu.arch == .aarch64);
    return asm volatile ("mrs %[value], s3_3_c4_c2_5"
        : [value] "=r" (-> u64),
    );
}

/// Writes AArch64's DIT register; as `readDit`.
pub inline fn writeDit(value: u64) void {
    comptime std.debug.assert(builtin.cpu.arch == .aarch64);
    asm volatile ("msr s3_3_c4_c2_5, %[value]"
        :
        : [value] "r" (value),
        : .{ .memory = true });
}

/// The kernel's hardware capability word (AT_HWCAP): Linux only.
pub fn hwcap() usize {
    comptime std.debug.assert(builtin.os.tag == .linux);
    return if (builtin.link_libc) std.c.getauxval(std.elf.AT.HWCAP) else std.os.linux.getauxval(std.elf.AT.HWCAP);
}

/// Linux's HWCAP bit for FEAT_DIT.
pub const hwcap_dit = if (builtin.os.tag == .linux) std.os.linux.HWCAP.DIT else 0;

/// The `bytes` of stack just below the calling frame, read as they are: inline, so the frame is
/// the caller's, which must be a frame of its own (noinline) whose callees used that stack.
pub inline fn stackBelow(comptime bytes: usize) *const volatile [bytes]u8 {
    return @ptrFromInt(@frameAddress() - bytes); // safe: the caller's frame lies above at least `bytes` of its thread's stack, which its callee just used
}

/// `value`, through an empty template whose tied register is opaque to the optimizer: a compiler
/// barrier, not a hardware timing guarantee. It emits no instruction on the targets that take it.
pub inline fn barrier(comptime T: type, value: T) T {
    return asm volatile (""
        : [out] "=r" (-> T),
        : [in] "0" (value),
    );
}
