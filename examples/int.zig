//! A record length computed from peer input: every step checked in every build, the result
//! narrowed to what the wire field holds, the bounds a type of their own.
const aegis = @import("aegis");

const int = aegis.int;
/// A TLS fragment length: 1 to 16384 bytes, checked wherever one is made.
const Fragment = int.Ranged(u16, 1, 16384);

fn recordLength(count: u32, width: u32, header: u32) !u32 {
    const body = try int.Checked(u32).init(count).mul(width);
    return (try body.add(header)).raw();
}

pub fn main() !void {
    aegis.assert.invariant(try recordLength(100, 40, 5) == 4005, "in range, the plain answer");
    if (recordLength(1 << 20, 1 << 20, 5)) |_| unreachable else |err| aegis.assert.invariant(err == error.Overflow, "overflow is an error, in ReleaseFast too");

    // Narrowing checks; widening cannot fail, so it carries no error at all.
    const wide: u64 = 70_000;
    if (int.cast(u16, wide)) |_| unreachable else |err| aegis.assert.invariant(err == error.Overflow, "70000 does not fit a u16");
    const widened: u64 = int.cast(u64, @as(u32, 7)); // no `try`: every u32 fits
    aegis.assert.invariant(widened == 7 and int.narrow(u8, wide) == null, "narrow is cast's optional form");

    // A range is part of the type: construction and arithmetic stay inside it.
    const fragment = try Fragment.init(16000);
    if (fragment.add(1000)) |_| unreachable else |err| aegis.assert.invariant(err == error.OutOfRange, "past 16384 is refused");
    const default = Fragment.literal(4096); // checked at compile time
    aegis.assert.invariant(default == Fragment.literal(4096), "a literal is checked where it is written");

    // Saturating arithmetic clamps where clamping is the meaning, and still refuses division by zero.
    // A plain `u8` where the value leaves for code that takes one.
    const credit: u8 = int.Saturating(u8).init(250).add(10).raw();
    aegis.assert.invariant(credit == 255, "clamped at the top");
    if (int.Saturating(u8).init(1).div(0)) |_| unreachable else |err| aegis.assert.invariant(err == error.DivisionByZero, "division by zero is never clamped");
}
