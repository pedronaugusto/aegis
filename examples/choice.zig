//! Checking a MAC and choosing between two blocks without branching on secrets: the decision
//! stays a `Choice` until the one place it is released.
const std = @import("std");
const aegis = @import("aegis");

const secret = aegis.secret;

/// Whether the received tag matches, released only as the final verdict.
fn verify(expected: *const [16]u8, received: *const [16]u8) bool {
    return secret.equal(16, expected, received).declassify("the verdict of a completed MAC check");
}

pub fn main() !void {
    const expected: [16]u8 = @splat(0x42);
    var received = expected;
    aegis.assert.invariant(verify(&expected, &received), "an equal tag verifies");
    received[15] ^= 1;
    aegis.assert.invariant(!verify(&expected, &received), "a tag one bit off does not");

    // Lengths are public: unequal ones are an error, never a quiet false.
    if (secret.equalBytes("abc", "abcd")) |_| unreachable else |err| aegis.assert.invariant(err == error.LengthMismatch, "lengths are compared in public");

    // Select reads both inputs whatever the choice, and writes the chosen one.
    const zero: [8]u8 = @splat(0);
    const block: [8]u8 = @splat(9);
    var out: [8]u8 = undefined;
    const pick = secret.equal(16, &expected, &expected);
    try pick.selectBytes(8, &out, &zero, &block);
    aegis.assert.invariant(std.mem.eql(u8, &out, &block), "a true choice selects the second block");

    // Big-endian comparison of two counters, every byte read, exactly one answer set.
    const order = secret.compareUnsigned(4, .big, &.{ 0, 0, 1, 0 }, &.{ 0, 0, 0, 255 });
    aegis.assert.invariant(order.gt.declassify("a public test of the comparison"), "256 is greater than 255");

    // Whether this build's lowering is one check-choices inspects; a consumer that needs the
    // evidence asserts it at compile time.
    std.mem.doNotOptimizeAway(secret.Choice.audited);
}
