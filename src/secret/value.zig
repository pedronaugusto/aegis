//! Byte-mask kernels. They compile for every target; the builds whose lowering
//! `zig build check-choices` inspects are listed in profiles.zig (docs/design.md).
const std = @import("std");
const builtin = @import("builtin");
const profiles = @import("profiles.zig");

/// Copyable one-bit decision. Explicit casts can bypass this API in Zig.
pub const Choice = packed struct(u1) {
    bit: u1,
    pub const FromBitError = error{InvalidBit};
    /// Whether this build is one whose lowering of these kernels `zig build check-choices`
    /// inspects: Zig 0.17.0's LLVM backend, a listed target and CPU model with that model's
    /// own features, and side-channel mitigations on. Other builds run the same source,
    /// without that evidence; a caller that requires it asserts this at compile time.
    pub const audited: bool = auditedBuild();
    /// The imported bit is PUBLIC; invalid values are rejected in every mode.
    pub inline fn fromBit(bit: u8) FromBitError!Choice {
        if (bit > 1) return error.InvalidBit;
        return fromKernel(bit);
    }
    pub inline fn @"and"(self: Choice, other: Choice) Choice {
        return fromKernel(@as(u32, self.bit & other.bit));
    }
    pub inline fn @"or"(self: Choice, other: Choice) Choice {
        return fromKernel(@as(u32, self.bit | other.bit));
    }
    pub inline fn xor(self: Choice, other: Choice) Choice {
        return fromKernel(@as(u32, self.bit ^ other.bit));
    }
    pub inline fn not(self: Choice) Choice {
        return fromKernel(@as(u32, self.bit ^ 1));
    }
    /// Only this explicit boundary releases a verdict for branching or logging.
    pub inline fn declassify(self: Choice, comptime reason: []const u8) bool {
        if (comptime std.mem.trim(u8, reason, " \t\r\n").len == 0) @compileError("Choice declassification requires a nonempty reason");
        return self.bit != 0;
    }
    /// Zero chooses a; one chooses b. Both inputs must already be initialized.
    pub inline fn selectInt(self: Choice, comptime T: type, a: T, b: T) T {
        const info = @typeInfo(T);
        if (info != .int) @compileError("Choice selectInt requires a fixed-width integer");
        const bits = info.int.bits;
        if (bits != 8 and bits != 16 and bits != 32 and bits != 64) @compileError("Choice selectInt supports only 8/16/32/64-bit integers");
        const unsigned = @Int(.unsigned, bits);
        const register = if (bits == 64) u64 else u32;
        const mask = barrier(register, 0 -% @as(register, self.bit));
        const inverse = barrier(register, ~mask);
        const x: unsigned = @bitCast(a); // safe: same-width representation, including signed integers
        const y: unsigned = @bitCast(b); // safe: same-width representation
        const value: unsigned = @truncate((@as(register, x) & inverse) | (@as(register, y) & mask)); // safe: retain exactly T's bits
        return @bitCast(value); // safe: every same-width integer bit pattern is valid
    }
    pub inline fn selectBytes(self: Choice, comptime N: usize, out: *[N]u8, a: *const [N]u8, b: *const [N]u8) SelectError!void {
        @setRuntimeSafety(true);
        if (partialOverlap(N, out, a) or partialOverlap(N, out, b)) return error.PartialOverlap;
        const mask = barrier(u32, 0 -% @as(u32, self.bit));
        const inverse = barrier(u32, ~mask);
        const x: *const volatile [N]u8 = a;
        const y: *const volatile [N]u8 = b;
        for (0..N) |i| {
            // Volatile loads of BOTH inputs precede the store, including exact aliases.
            const av = x[i];
            const bv = y[i];
            out[i] = @truncate((@as(u32, av) & inverse) | (@as(u32, bv) & mask)); // safe: byte result
        }
    }
    pub fn format(_: Choice, _: *std.Io.Writer) std.Io.Writer.Error!void {
        @compileError("ChoiceNotFormattable: explicitly declassify a completed verdict");
    }
};
pub const OrderChoices = struct { lt: Choice, eq: Choice, gt: Choice };
pub const CompareError = error{LengthMismatch};
pub const SelectError = error{PartialOverlap};

pub inline fn equal(comptime N: usize, a: *const [N]u8, b: *const [N]u8) Choice {
    return equalKernel(a, b);
}
/// Lengths and addresses are public. Every byte of the common length is read.
pub inline fn equalBytes(a: []const u8, b: []const u8) CompareError!Choice {
    @setRuntimeSafety(true);
    if (a.len != b.len) return error.LengthMismatch;
    return equalKernel(a, b);
}
inline fn equalKernel(a: []const u8, b: []const u8) Choice {
    @setRuntimeSafety(true);
    const x: [*]const volatile u8 = a.ptr;
    const y: [*]const volatile u8 = b.ptr;
    var difference: u32 = 0;
    for (0..a.len) |i| difference |= @as(u32, x[i] ^ y[i]);
    // difference is 0..255; wrapping subtract has high byte set only at zero.
    return fromKernel(((barrier(u32, difference) -% 1) >> 8) & 1);
}
/// Endian is PUBLIC. The first unequal most-significant byte determines order.
pub inline fn compareUnsigned(comptime N: usize, endian: std.lang.Endian, a: *const [N]u8, b: *const [N]u8) OrderChoices {
    @setRuntimeSafety(true);
    const x: *const volatile [N]u8 = a;
    const y: *const volatile [N]u8 = b;
    var eq: u32 = 1;
    var lt: u32 = 0;
    var gt: u32 = 0;
    for (0..N) |j| {
        const i = if (endian == .big) j else N - 1 - j;
        const av: u32 = x[i];
        const bv: u32 = y[i];
        lt |= (((av -% bv) >> 8) & 1) & eq;
        gt |= (((bv -% av) >> 8) & 1) & eq;
        eq &= (((av ^ bv) -% 1) >> 8) & 1;
    }
    return .{ .lt = fromKernel(lt), .eq = fromKernel(eq), .gt = fromKernel(gt) };
}
inline fn fromKernel(bit: u32) Choice {
    return .{ .bit = @truncate(barrier(u32, bit)) }; // safe: kernels establish 0/1; truncation never branches
}
inline fn barrier(comptime T: type, value: T) T {
    // The tied register is opaque to LLVM; it emits no instruction on enabled ISAs.
    // This is a compiler barrier, not a hardware timing guarantee.
    return asm volatile (""
        : [out] "=r" (-> T),
        : [in] "0" (value),
    );
}
inline fn partialOverlap(comptime N: usize, out: *[N]u8, source: *const [N]u8) bool {
    const d = @intFromPtr(out); // safe: live address used only for public extent validation
    const s = @intFromPtr(source); // safe: live address used only for public extent validation
    if (d == s or N == 0) return false;
    // Ordered subtraction avoids address-end overflow, even at the top of usize.
    return if (d > s) d - s < N else s - d < N;
}
fn auditedBuild() bool {
    if (builtin.zig_version.major != 0 or builtin.zig_version.minor != 17 or builtin.zig_version.patch != 0 or builtin.zig_version.pre != null) return false;
    if (builtin.zig_backend != .stage2_llvm) return false;
    if (std.options.side_channels_mitigations == .none) return false;
    @setEvalBranchQuota(100_000);
    for (profiles.all) |profile| {
        // unreachable: every listed profile parses; the A5 test parses each one.
        const query = std.Target.Query.parse(.{ .arch_os_abi = profile.target, .cpu_features = profile.cpu }) catch unreachable;
        const arch = query.cpu_arch.?;
        const os = query.os_tag.?;
        if (builtin.target.cpu.arch != arch or builtin.target.os.tag != os) continue;
        if (query.abi) |abi| if (builtin.target.abi != abi) continue;
        const cpu = switch (query.cpu_model) {
            .baseline => std.Target.Cpu.baseline(arch, builtin.target.os),
            .explicit => |model| model.toCpu(arch),
            // unreachable: a listed CPU is "baseline" or a model name.
            else => unreachable,
        };
        if (std.mem.eql(u8, builtin.target.cpu.model.name, cpu.model.name) and builtin.target.cpu.features.eql(cpu.features)) return true;
    }
    return false;
}
