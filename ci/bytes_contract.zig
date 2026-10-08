//! All-build invalid descriptor move must fail before corrupting ownership.
const std = @import("std");
const aegis = @import("aegis");
pub fn main(_: std.process.Init) void {
    var owner = aegis.SecretBytes.init(std.heap.page_allocator, 0) catch @panic("allocation failure");
    owner.moveInto(&owner);
    @panic("overlapping secret move accepted");
}
