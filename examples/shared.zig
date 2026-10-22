//! A parsed certificate the parser and a connection both hold: counted shared ownership of
//! one allocation, cleaned by whichever release is last, on whichever task makes it.
const std = @import("std");
const aegis = @import("aegis");

const Certificate = struct { serial: u64, cleaned: *bool };

fn forget(certificate: *Certificate) void {
    certificate.cleaned.* = true;
}

const Held = aegis.Shared(Certificate, forget);

pub fn main(init: std.process.Init) !void {
    var cleaned = false;
    var parsed = try Held.create(init.gpa, .{ .serial = 7, .cleaned = &cleaned });
    // A second handle by `retain`, never by copying one; it may go to another task.
    var connection = parsed.retain();
    parsed.release();
    aegis.assert.post(!cleaned and connection.get().serial == 7, "one handle still holds it");
    connection.release(); // the last release runs the cleanup and frees the block
    aegis.assert.post(cleaned, "cleaned once, by the last release");
}
