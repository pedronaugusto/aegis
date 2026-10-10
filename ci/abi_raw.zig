//! Separate translation unit: every exported C prototype uses only raw integers.
// 128-bit integers are deliberately outside the promised C ABI profile.
pub const representations = .{ u8, i8, u16, i16, u32, i32, u64, i64, usize, isize };
pub fn Raw(comptime R: type) type {
    return struct {
        pub const Record = extern struct { before: u8, value: R, after: R };
        fn exchange(value: R, salt: R) callconv(.c) R {
            return value ^ salt;
        }
        fn field(record: *const Record) callconv(.c) R {
            // safe: masking to 0..127 is representable by every supported signed/unsigned R.
            return record.value ^ record.after ^ @as(R, @intCast(record.before & 0x7f));
        }
    };
}
comptime {
    for (representations) |R| {
        @export(&Raw(R).exchange, .{ .name = "raw_exchange_" ++ @typeName(R) });
        @export(&Raw(R).field, .{ .name = "raw_field_" ++ @typeName(R) });
    }
}
