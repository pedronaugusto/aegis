//! Externally serialized issuer. Caller supplies a unique namespace and persists continuity.
const Domain = @This();
const std = @import("std");
pub const Instance = struct {
    namespace: u128,
    serial: u64,
    pub fn eql(a: Instance, b: Instance) bool {
        return a.namespace == b.namespace and a.serial == b.serial;
    }
};
pub const IssueError = error{InstanceExhausted};
namespace: u128,
last: u64 = 0,
pub fn init(namespace: u128) Domain {
    return .{ .namespace = namespace };
}
pub fn issue(self: *Domain) IssueError!Instance {
    if (self.last == std.math.maxInt(u64)) return error.InstanceExhausted;
    self.last += 1;
    return .{ .namespace = self.namespace, .serial = self.last };
}
