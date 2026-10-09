//! A program may mix root and standalone namespaces without duplicating declarations.
const std = @import("std");
const a = @import("aegis");
const secret = @import("aegis.secret");
const sync = @import("aegis.sync");
const id = @import("aegis.id");
const units = @import("aegis.units");
const int = @import("aegis.int");
const assert = @import("aegis.assert");
const handle = @import("aegis.handle");
const input = @import("aegis.input");
const err = @import("aegis.err");
comptime {
    std.debug.assert(a.Secret == secret.Secret);
    std.debug.assert(a.SecretBytes == secret.SecretBytes);
    std.debug.assert(a.secret.Choice == secret.Choice);
    std.debug.assert(a.Guarded == sync.Guarded);
    std.debug.assert(a.id.Id == id.Id);
    std.debug.assert(a.units.Bytes == units.Bytes);
    std.debug.assert(a.int.Checked == int.Checked);
    std.debug.assert(a.assert.invariant == assert.invariant);
    std.debug.assert(a.handle.Pool == handle.Pool);
    std.debug.assert(a.input.Untrusted == input.Untrusted);
    std.debug.assert(a.err.Context == err.Context);
}
pub fn main() void {}
