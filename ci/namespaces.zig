//! A program may mix root and standalone namespaces without duplicating declarations.
const std = @import("std");
const a = @import("aegis");
comptime {
    std.debug.assert(a.Secret == @import("aegis.secret").Secret);
    std.debug.assert(a.SecretBytes == @import("aegis.secret").SecretBytes);
    std.debug.assert(a.secret.Choice == @import("aegis.secret").Choice);
    std.debug.assert(a.Guarded == @import("aegis.sync").Guarded);
    std.debug.assert(a.id.Id == @import("aegis.id").Id);
    std.debug.assert(a.units.Bytes == @import("aegis.units").Bytes);
    std.debug.assert(a.int.Checked == @import("aegis.int").Checked);
    std.debug.assert(a.assert.invariant == @import("aegis.assert").invariant);
    std.debug.assert(a.handle.Pool == @import("aegis.handle").Pool);
    std.debug.assert(a.input.Untrusted == @import("aegis.input").Untrusted);
    std.debug.assert(a.err.Context == @import("aegis.err").Context);
}
pub fn main() void {}
