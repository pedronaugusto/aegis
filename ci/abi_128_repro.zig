//! Minimal Zig 0.17 x86_64-windows C return-ABI control; no aegis imports.
const E = enum(u128) { zero = 0, _ };
extern fn raw_exchange_u128(u128, u128) u128;
const typed = @extern(*const fn (E, E) callconv(.c) E, .{ .name = "raw_exchange_u128" });
export fn typedCaller(x: u128, salt: u128) u128 {
    return @backingInt(typed(@fromBackingInt(x), @fromBackingInt(salt)));
}
export fn rawCaller(x: u128, salt: u128) u128 {
    return raw_exchange_u128(x, salt);
}
