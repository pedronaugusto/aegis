//! Explicit inline ownership and short spin-guarded data. Runtime closure: std only.
/// Inline secret storage with explicit exposure, transfer and unconditional erasure.
pub const Secret = secret.Secret;
/// Owned secret bytes with explicit full capacity and unconditional pre-free erasure.
pub const SecretBytes = secret.SecretBytes;
/// Data beside its acquire/release spin lock; guards borrow until release.
pub const Guarded = sync.Guarded;
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
/// Comptime typestate machines, staged payloads and a checked runtime transition table.
pub const state = @import("state.zig");
/// Scope lifetimes: a brand and a generation that catch a reference used after its scope ended.
pub const scope = @import("scope.zig");
/// Exclusive std.Io.Mutex guards, with explicit Io release.
pub const BlockingGuarded = sync.BlockingGuarded;
/// Bounded std.Io.RwLock guards with immutable/mutable borrows.
pub const RwGuarded = sync.RwGuarded;
/// Bounded condition waiters with guard reacquisition on every return.
pub const Condition = sync.Condition;
/// Stable initialization, retry and acquire/release publication.
pub const Once = sync.Once;
/// Leaf initialization under the election mutex: no task context, the initializer's own errors.
pub const Lazy = sync.Lazy;
/// A lock-free cell for one id, count, unit or plain enum, read and written whole.
pub const Atomic = sync.Atomic;
/// Counted shared ownership of one allocated value, cleaned by the last release.
pub const Shared = sync.Shared;
/// Explicit logical-task initializer stack; zero-sized in release.
pub const InitContext = sync.InitContext;
/// Comptime partial rank relation with Debug logical-task diagnostics.
pub const Order = sync.Order;
/// Checked single-task state in Debug/ReleaseSafe, plain payload in fast/small.
pub const Confined = sync.Confined;
/// Stable caller-issued logical-task identity for Confined.
pub const TaskIdentity = sync.TaskIdentity;

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("secret.zig");

/// Checked generational keys and typed positions; owners require external synchronization.
pub const handle = @import("handle.zig");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input.zig");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err.zig");

/// Synchronization and logical-task contracts sharing the root aliases.
pub const sync = @import("sync.zig");
