//! Explicit inline ownership and short spin-guarded data. Runtime closure: std only.
/// Inline secret storage with explicit exposure, transfer and unconditional erasure.
pub const Secret = @import("Secret.zig").Secret;
/// Owned secret bytes with explicit full capacity and unconditional pre-free erasure.
pub const SecretBytes = @import("SecretBytes.zig");
/// Data beside its acquire/release spin lock; guards borrow until release.
pub const Guarded = @import("Guarded.zig").Guarded;
/// All-build checked, saturating and ranged scalar arithmetic and failing casts.
pub const int = @import("int.zig");
/// Distinct scalar identity domains and nonwrapping externally serialized issuers.
pub const id = @import("id.zig");
/// Explicit scalar units, duration scales and clock domains.
pub const units = @import("units.zig");
/// Always-on programmer contracts and explicitly optional diagnostics.
pub const assert = @import("assert.zig");
/// Bounded single-owner storage and explicit finite admission.
pub const bounded = @import("bounded.zig");
/// Static nonblocking cleanup owners and explicit result obligations.
pub const own = @import("own.zig");
/// Exclusive std.Io.Mutex guards, with explicit Io release.
pub const BlockingGuarded = @import("BlockingGuarded.zig").BlockingGuarded;
/// Bounded std.Io.RwLock guards with immutable/mutable borrows.
pub const RwGuarded = @import("RwGuarded.zig").RwGuarded;
/// Bounded condition waiters with guard reacquisition on every return.
pub const Condition = @import("Condition.zig");
/// Stable initialization, retry and acquire/release publication.
pub const Once = @import("Once.zig").Once;
/// Explicit logical-task initializer stack; zero-sized in release.
pub const InitContext = @import("Once.zig").InitContext;
/// Comptime partial rank relation with Debug logical-task diagnostics.
pub const Order = @import("Order.zig").Order;
/// Checked single-task state in Debug/ReleaseSafe, plain payload in fast/small.
pub const Confined = @import("Confined.zig").Confined;
/// Stable caller-issued logical-task identity for Confined.
pub const TaskIdentity = @import("Confined.zig").Identity;

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("constant_time.zig");
