const std = @import("std");
const cases = @import("choice_callers.zig");
const option = @import("profile");
pub const std_options: std.Options = .{ .side_channels_mitigations = option.mitigation };
export fn baselineEqual0(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal0", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperEqual0(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal0", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineEqual1(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal1", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperEqual1(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal1", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineEqual32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal32", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperEqual32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal32", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineEqual48(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal48", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperEqual48(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal48", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineEqual512(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal512", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperEqual512(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("equal512", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineDynamic(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("dynamic", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperDynamic(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("dynamic", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineOrderBig(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_big", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperOrderBig(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_big", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineOrderLittle(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_little", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperOrderLittle(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_little", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineOrderRuntime(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_runtime", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperOrderRuntime(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("order_runtime", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineInt8(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int8", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperInt8(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int8", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineInt16(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int16", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperInt16(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int16", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineInt32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int32", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperInt32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int32", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineInt64(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int64", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperInt64(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("int64", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineLogic(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("logic", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperLogic(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("logic", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineBytes(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("bytes", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperBytes(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("bytes", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineAlias(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("alias", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperAlias(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("alias", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineMontgomery(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("montgomery", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperMontgomery(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("montgomery", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineCurve(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("curve", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperCurve(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("curve", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineOffline(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("offline", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperOffline(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("offline", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineFinished(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("finished", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperFinished(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("finished", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineDead(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("dead", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperDead(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("dead", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineSigned8(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed8", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperSigned8(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed8", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineSigned16(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed16", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperSigned16(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed16", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineSigned32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed32", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperSigned32(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed32", true, out, a, b, len, if (endian == 0) .big else .little);
}
export fn baselineSigned64(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed64", false, out, a, b, len, if (endian == 0) .big else .little);
}
export fn wrapperSigned64(out: *[512]u8, a: *const [512]u8, b: *const [512]u8, len: usize, endian: u8) u64 {
    return cases.run("signed64", true, out, a, b, len, if (endian == 0) .big else .little);
}
// Deliberately unsafe test-only controls: the A5 detector must reject them.
export fn leakBranch(a: *const [512]u8, b: *const [512]u8, out: *[512]u8) u64 {
    const av: *const volatile [512]u8 = a;
    const bv: *const volatile [512]u8 = b;
    const value = if (av[0] == 0) bv[1] else bv[2];
    out[0] = value;
    return value;
}
export fn leakIndex(a: *const [512]u8, b: *const [512]u8, out: *[512]u8) u64 {
    const av: *const volatile [512]u8 = a;
    const bv: *const volatile [512]u8 = b;
    const value = bv[av[0]];
    out[0] = value;
    return value;
}
