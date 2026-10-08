//! Aegis declarations call separately compiled RAW INTEGER exports, never typed mirrors.
const std = @import("std");
const a = @import("aegis");
const Tag = struct {};
// C ABI profile: 8–64-bit and pointer-width integers. 128-bit reprs remain Zig types only.
const representations = .{ u8, i8, u16, i16, u32, i32, u64, i64, usize, isize };
// Deliberate unchecked foreign representation fixtures also run against old A3.
fn importRepresentation(comptime T: type, value: anytype) T {
    if (comptime @typeInfo(T) == .@"enum") return @fromBackingInt(value);
    var out: T = undefined;
    @field(out, @typeInfo(T).@"struct".field_names[0]) = value;
    return out;
}
fn representation(value: anytype) if (@typeInfo(@TypeOf(value)) == .@"enum") @typeInfo(@TypeOf(value)).@"enum".tag_type else @typeInfo(@TypeOf(value)).@"struct".field_types[0] {
    if (comptime @typeInfo(@TypeOf(value)) == .@"enum") return @backingInt(value);
    return @field(value, @typeInfo(@TypeOf(value)).@"struct".field_names[0]);
}
fn Fixture(comptime T: type, comptime R: type) type {
    return struct {
        const Record = extern struct { before: u8, value: T, after: R };
        const RawRecord = extern struct { before: u8, value: R, after: R };
        const typed_exchange = @extern(*const fn (T, T) callconv(.c) T, .{ .name = "raw_exchange_" ++ @typeName(R) });
        const raw_exchange = @extern(*const fn (R, R) callconv(.c) R, .{ .name = "raw_exchange_" ++ @typeName(R) });
        const typed_field = @extern(*const fn (*const Record) callconv(.c) T, .{ .name = "raw_field_" ++ @typeName(R) });
        const raw_field = @extern(*const fn (*const RawRecord) callconv(.c) R, .{ .name = "raw_field_" ++ @typeName(R) });
        fn call(value: R, salt: R) callconv(.c) R {
            // Deliberate unchecked representation import tests ABI, not domain validity.
            return representation(typed_exchange(importRepresentation(T, value), importRepresentation(T, salt)));
        }
        fn baseline(value: R, salt: R) callconv(.c) R {
            return raw_exchange(value, salt);
        }
        fn field(value: R, salt: R) callconv(.c) R {
            // Deliberately forge ABI field storage; consumers validate imported domains.
            const record: Record = .{ .before = 1, .value = importRepresentation(T, value), .after = salt };
            return representation(typed_field(&record));
        }
        fn baselineField(value: R, salt: R) callconv(.c) R {
            const record: RawRecord = .{ .before = 1, .value = value, .after = salt };
            return raw_field(&record);
        }
        fn nativeCheck() !void {
            for ([_]R{ std.math.minInt(R), std.math.maxInt(R), 1 }) |value| {
                const salt: R = 1;
                if (call(value, salt) != (value ^ salt)) return error.ArgumentOrReturnAbiMismatch;
                if (field(value, salt) != (value ^ salt ^ 1)) return error.RecordAbiMismatch;
            }
        }
    };
}
fn prove(comptime T: type, comptime R: type, comptime suffix: []const u8) void {
    const F = Fixture(T, R);
    if (@sizeOf(T) != @sizeOf(R) or @alignOf(T) != @alignOf(R)) @compileError("scalar ABI layout differs");
    if (@sizeOf(F.Record) != @sizeOf(F.RawRecord) or @alignOf(F.Record) != @alignOf(F.RawRecord) or @offsetOf(F.Record, "value") != @offsetOf(F.RawRecord, "value") or @offsetOf(F.Record, "after") != @offsetOf(F.RawRecord, "after")) @compileError("record ABI layout differs");
    @export(&F.call, .{ .name = "typed_" ++ suffix });
    @export(&F.baseline, .{ .name = "baseline_" ++ suffix });
    @export(&F.field, .{ .name = "typed_field_" ++ suffix });
    @export(&F.baselineField, .{ .name = "baseline_field_" ++ suffix });
}
fn Types(comptime R: type) type {
    return struct {
        const values = .{ a.id.Id(Tag, R), a.id.NonZero(Tag, R), a.units.Count(Tag, R), a.units.Bytes(R), a.units.Bits(R), a.units.Duration(.nanosecond, R), a.units.Instant(.awake, .nanosecond, R), a.int.Ranged(R, 0, 1) };
    };
}
comptime {
    @setEvalBranchQuota(2000000);
    for (representations) |R| {
        for (Types(R).values, 0..) |T, index| prove(T, R, std.fmt.comptimePrint("{s}_{d}", .{ @typeName(R), index }));
        for (std.meta.tags(a.units.Unit)) |unit| {
            prove(a.units.Duration(unit, R), R, std.fmt.comptimePrint("duration_{s}_{s}", .{ @typeName(R), @tagName(unit) }));
            for (std.meta.tags(std.Io.Clock)) |clock| prove(a.units.Instant(clock, unit, R), R, std.fmt.comptimePrint("instant_{s}_{s}_{s}", .{ @typeName(R), @tagName(unit), @tagName(clock) }));
        }
        if (@typeInfo(R).int.signedness == .unsigned) prove(a.id.Counter(Tag, R), R, "counter_" ++ @typeName(R));
    }
}
pub fn nativeCheck() !void {
    @setEvalBranchQuota(2000000);
    inline for (representations) |R| {
        inline for (Types(R).values) |T| try Fixture(T, R).nativeCheck();
        inline for (comptime std.meta.tags(a.units.Unit)) |unit| {
            try Fixture(a.units.Duration(unit, R), R).nativeCheck();
            inline for (comptime std.meta.tags(std.Io.Clock)) |clock| try Fixture(a.units.Instant(clock, unit, R), R).nativeCheck();
        }
        if (comptime @typeInfo(R).int.signedness == .unsigned) try Fixture(a.id.Counter(Tag, R), R).nativeCheck();
    }
}
