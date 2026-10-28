//! Why a certificate was refused, carried beside the error without allocating: a few public
//! frames inline, the first ones kept, truncation marked.
const std = @import("std");
const aegis = @import("aegis");

const err = aegis.err;

/// Only public facts: the frame type says so, and pointers or slices would not compile.
const Frame = struct {
    pub const aegis_public_frame = true;
    stage: enum { decode, chain, policy },
    depth: u8,
    field: err.PublicText(12),
};

const Refusal = err.Failure(error{ BadCertificate, UntrustedRoot }, Frame, 2);

fn verify(chain_length: u8) Refusal {
    var failure: Refusal = .{ .cause = error.UntrustedRoot };
    var depth: u8 = 0;
    while (depth < chain_length) : (depth += 1) {
        failure.context.push(.{ .stage = .chain, .depth = depth, .field = .literal("issuer") });
    }
    return failure;
}

pub fn main() !void {
    const refusal = verify(3);
    aegis.assert.invariant(refusal.cause == error.UntrustedRoot, "the cause is the error itself");
    aegis.assert.invariant(refusal.context.frames().len == 2 and refusal.context.truncated, "the first two frames kept, the third marked");

    var line: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&line);
    try refusal.context.format(&writer);
    aegis.assert.invariant(std.mem.endsWith(u8, writer.buffered(), "[truncated]"), "written without allocating");

    // Runtime text enters a frame only by a stated classification, escaped into fixed storage.
    const name = err.PublicText(12).copy(.classify("a certificate subject is public", "CN=a\nb"));
    aegis.assert.invariant(std.mem.eql(u8, name.view(), "CN=a\\x0ab"), "control bytes escaped");
}
