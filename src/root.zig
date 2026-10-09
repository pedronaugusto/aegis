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

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("secret");

/// Checked generational keys and typed positions; owners require external synchronization.
pub const handle = @import("handle");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err");

/// Spin synchronization; namespace declarations share the root aliases.
pub const sync = @import("sync");
