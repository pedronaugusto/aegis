//! Explicit inline ownership and short spin-guarded data. Runtime closure: std only.
/// Inline secret storage with explicit exposure, transfer and unconditional erasure.
pub const Secret = secret.Secret;
/// Owned secret bytes with explicit full capacity and unconditional pre-free erasure.
pub const SecretBytes = secret.SecretBytes;
/// Data beside its acquire/release spin lock; guards borrow until release.
pub const Guarded = sync.Guarded;
/// All-build checked, saturating and ranged scalar arithmetic and failing casts.
pub const int = @import("int");
/// Distinct scalar identity domains and nonwrapping externally serialized issuers.
pub const id = @import("id");
/// Explicit scalar units, duration scales and clock domains.
pub const units = @import("units");
/// Always-on programmer contracts and explicitly optional diagnostics.
pub const assert = @import("assert");

/// Bounded single-owner storage and explicit finite admission.
pub const bounded = @import("bounded");
/// Static nonblocking cleanup owners and explicit result obligations.
pub const own = @import("own");
/// Exclusive std.Io.Mutex guards, with explicit Io release.
pub const BlockingGuarded = sync.BlockingGuarded;
/// Bounded std.Io.RwLock guards with immutable/mutable borrows.
pub const RwGuarded = sync.RwGuarded;
/// Bounded condition waiters with guard reacquisition on every return.
pub const Condition = sync.Condition;
/// Stable initialization, retry and acquire/release publication.
pub const Once = sync.Once;
/// Explicit logical-task initializer stack; zero-sized in release.
pub const InitContext = sync.InitContext;
/// Comptime partial rank relation with Debug logical-task diagnostics.
pub const Order = sync.Order;
/// Checked single-task state in Debug/ReleaseSafe, plain payload in fast/small.
pub const Confined = sync.Confined;
/// Stable caller-issued logical-task identity for Confined.
pub const TaskIdentity = sync.TaskIdentity;

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("secret");

/// Checked generational keys and typed positions; owners require external synchronization.
pub const handle = @import("handle");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err");

/// Synchronization and logical-task contracts sharing the root aliases.
pub const sync = @import("sync");
