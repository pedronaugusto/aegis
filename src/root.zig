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

/// Copyable choices and audited byte comparison/select kernels.
pub const secret = @import("constant_time.zig");

/// Checked generational keys and typed positions; owners require external synchronization.
pub const handle = @import("handle.zig");
/// Boundary markers preserving each parser's exact error and refined result contract.
pub const input = @import("input.zig");
/// Allocation-free closed public diagnostic frames.
pub const err = @import("err.zig");
