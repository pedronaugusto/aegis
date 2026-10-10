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
const bounded = @import("aegis.bounded");
const own = @import("aegis.own");
const state = @import("aegis.state");
const scope = @import("aegis.scope");
comptime {
    std.debug.assert(a.Secret == secret.Secret);
    std.debug.assert(a.SecretBytes == secret.SecretBytes);
    std.debug.assert(a.secret.Choice == secret.Choice);
    std.debug.assert(a.Guarded == sync.Guarded);
    std.debug.assert(a.BlockingGuarded == sync.BlockingGuarded);
    std.debug.assert(a.RwGuarded == sync.RwGuarded);
    std.debug.assert(a.Condition == sync.Condition);
    std.debug.assert(a.Once == sync.Once);
    std.debug.assert(a.InitContext == sync.InitContext);
    std.debug.assert(a.Lazy == sync.Lazy);
    std.debug.assert(a.Shared == sync.Shared);
    std.debug.assert(a.Order == sync.Order);
    std.debug.assert(a.Confined == sync.Confined);
    std.debug.assert(a.TaskIdentity == sync.TaskIdentity);
    std.debug.assert(a.bounded.Array == bounded.Array);
    std.debug.assert(a.own.Owned == own.Owned);
    std.debug.assert(a.id.Id == id.Id);
    std.debug.assert(a.units.Bytes == units.Bytes);
    std.debug.assert(a.int.Checked == int.Checked);
    std.debug.assert(a.assert.invariant == assert.invariant);
    std.debug.assert(a.handle.Pool == handle.Pool);
    std.debug.assert(a.input.Untrusted == input.Untrusted);
    std.debug.assert(a.err.Context == err.Context);
    std.debug.assert(a.state.Machine == state.Machine);
    std.debug.assert(a.scope.Table == scope.Table);
    std.debug.assert(a.scope.Ref == scope.Ref);
}
pub fn main() void {}
