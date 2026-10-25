//! A private key read in pieces: allocated bytes owned with their full capacity, grown
//! without leaving the old copy behind, moved to where they live, wiped before they are freed.
const std = @import("std");
const aegis = @import("aegis");

pub fn main(init: std.process.Init) !void {
    var kept: aegis.SecretBytes = undefined;
    {
        // Capacity is explicit and zeroed; the live length starts at zero.
        var key = try aegis.SecretBytes.init(init.gpa, 16);
        errdefer key.deinit(init.gpa); // wipes the whole capacity before freeing it, in every build mode
        try key.replace("-----BEGIN KEY");
        aegis.assert.post(key.len() == 14 and key.capacity() == 16, "the live prefix sits in its capacity");

        // Growing never resizes in place: a new allocation, the old one wiped and freed.
        try key.reserve(init.gpa, 64);
        try key.resizeWithinCapacity(14 + 5);
        @memcpy(key.exposeMut()[14..], "-----");
        aegis.assert.post(std.mem.eql(u8, key.expose(), "-----BEGIN KEY-----"), "the bytes moved with the reserve");

        // Input that does not fit is refused before anything changes.
        const too_long: [65]u8 = @splat('x');
        if (key.replace(&too_long)) |_| unreachable else |err| aegis.assert.invariant(err == error.CapacityExceeded, "capacity is a limit");
        aegis.assert.post(key.len() == 19, "a refused replace changed nothing");

        // The owner moves to where it lives; the allocation goes with it, no byte copied.
        key.moveInto(&kept);
    }
    defer kept.deinit(init.gpa);
    aegis.assert.post(kept.len() == 19, "the moved owner holds the key");
}
