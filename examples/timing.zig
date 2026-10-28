//! A secret computation run as one span: data-independent timing on where the processor has
//! it, and the stack its callees used zeroed once it returns.
const std = @import("std");
const aegis = @import("aegis");

const secret = aegis.secret;

/// Stands for work on a key: whatever it spills lands in the frames below its caller.
fn mix(key: *const [32]u8, nonce: u64) u64 {
    var state: u64 = nonce;
    for (key) |byte| state = std.hash.int(state ^ byte);
    return state;
}

pub fn main() !void {
    const key: [32]u8 = @splat(3);
    // How deep the computation writes, measured: the scrub must reach at least that far.
    const reach = secret.stackReach(4096, mix, .{ &key, 1 });
    aegis.assert.invariant(reach <= 4096, "the computation fits the measured window");

    // `scrubbed` runs it under `Timing`, in a frame of its own, then scrubs 4 KiB below.
    const tag = secret.scrubbed(4096, mix, .{ &key, 1 });
    aegis.assert.invariant(tag == mix(&key, 1), "the span changes timing and stack, not the answer");

    // The same span by hand: the mode is on inside, back to what it was after.
    {
        const timing = secret.Timing.begin();
        defer timing.end();
        aegis.assert.invariant(secret.Timing.active() == secret.Timing.supported(), "on exactly where the processor has the mode");
    }
    secret.scrubStack(256);
}
