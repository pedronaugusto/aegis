//! Force branded C calls, returned types and C record fields for every ABI repr.
const std = @import("std");
const a = @import("aegis");
const Tag = struct {};
fn Fixture(comptime T: type) type {
    return struct {
        // The call forces analysis of the extern declaration, not just its type.
        extern fn exchange(value: T) T;
        fn call(value: T) callconv(.c) T {
            return exchange(value);
        }
    };
}
comptime {
    @setEvalBranchQuota(2000000);
    for (.{ u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, usize, isize }) |R| {
        const types = .{ a.id.Id(Tag, R), a.id.NonZero(Tag, R), a.units.Count(Tag, R), a.units.Bytes(R), a.units.Bits(R), a.units.Duration(.nanosecond, R), a.units.Instant(.awake, .nanosecond, R), a.int.Ranged(R, 0, 1) };
        for (types, 0..) |T, index| {
            const Record = extern struct { value: T };
            const RawRecord = extern struct { value: R };
            if (@sizeOf(T) != @sizeOf(R) or @alignOf(T) != @alignOf(R)) @compileError("scalar ABI layout differs");
            if (@sizeOf(Record) != @sizeOf(RawRecord) or @alignOf(Record) != @alignOf(RawRecord) or @offsetOf(Record, "value") != @offsetOf(RawRecord, "value")) @compileError("record ABI layout differs");
            @export(&Fixture(T).call, .{ .name = std.fmt.comptimePrint("abi_{s}_{d}", .{ @typeName(R), index }) });
        }
        for (std.meta.tags(a.units.Unit)) |unit| {
            const D = a.units.Duration(unit, R);
            const DurationRecord = extern struct { value: D };
            if (@sizeOf(DurationRecord) != @sizeOf(R) or @alignOf(DurationRecord) != @alignOf(R)) @compileError("duration ABI layout differs");
            @export(&Fixture(D).call, .{ .name = std.fmt.comptimePrint("abi_duration_{s}_{s}", .{ @typeName(R), @tagName(unit) }) });
            for (std.meta.tags(std.Io.Clock)) |clock| {
                const I = a.units.Instant(clock, unit, R);
                const InstantRecord = extern struct { value: I };
                if (@sizeOf(InstantRecord) != @sizeOf(R) or @alignOf(InstantRecord) != @alignOf(R)) @compileError("instant ABI layout differs");
                @export(&Fixture(I).call, .{ .name = std.fmt.comptimePrint("abi_instant_{s}_{s}_{s}", .{ @typeName(R), @tagName(unit), @tagName(clock) }) });
            }
        }
        if (@typeInfo(R).int.signedness == .unsigned) {
            const T = a.id.Counter(Tag, R);
            const Record = extern struct { value: T };
            if (@sizeOf(Record) != @sizeOf(R) or @alignOf(Record) != @alignOf(R)) @compileError("issuer ABI layout differs");
            @export(&Fixture(T).call, .{ .name = "abi_counter_" ++ @typeName(R) });
        }
    }
}
