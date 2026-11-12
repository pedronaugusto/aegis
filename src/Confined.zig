//! Checked single logical-task ownership for otherwise reachable shared state.
const builtin = @import("builtin");
const checked = builtin.optimize == .debug or builtin.optimize == .safe;

/// Caller issues stable unique identities for logical tasks. No threadlocal identity.
/// External synchronization establishes quiescent handoff; this is not a lock.
pub const Identity = enum(usize) { _ };

/// Identity/access/handoff checks remain in Debug and ReleaseSafe.
/// ReleaseFast/Small stores only T. Does not prove borrow expiry or exclusivity of raw aliases.
pub fn Confined(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Private: only access as the owner.
        aegis_data: T,
        /// Private: checked logical-task identity; zero-sized in fast/small.
        aegis_owner: if (checked) Identity else void,
        pub fn init(identity: Identity, initial: T) Self {
            return .{ .aegis_data = initial, .aegis_owner = if (checked) identity else {} };
        }
        fn check(self: *const Self, identity: Identity) void {
            if (checked and self.aegis_owner != identity) @panic("Confined accessed by another logical task");
        }
        pub fn value(self: *Self, identity: Identity) *T {
            self.check(identity);
            return &self.aegis_data;
        }
        pub fn valueConst(self: *const Self, identity: Identity) *const T {
            self.check(identity);
            return &self.aegis_data;
        }
        /// Current owner authorizes transfer while all earlier borrows are gone.
        /// Publishing the new identity/access is the consumer's synchronized operation.
        pub fn handOff(self: *Self, current: Identity, next: Identity) void {
            self.check(current);
            if (checked) self.aegis_owner = next;
        }
    };
}
