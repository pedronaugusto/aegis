//! A4 surface regression: the published pre-A4 root must reject this fixture.
const std = @import("std");
const aegis = @import("aegis");
export fn ownerSurface(gpa: *const std.mem.Allocator) void {
    var owner = aegis.SecretBytes.init(gpa.*, 0) catch @panic("public allocation failure");
    owner.resizeWithinCapacity(0) catch @panic("public capacity failure");
    owner.replace(&.{}) catch @panic("public replacement failure");
    owner.reserve(0) catch @panic("public reserve failure");
    var destination: aegis.SecretBytes = undefined;
    owner.moveInto(&destination);
    destination.deinit();
}
