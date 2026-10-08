//! Explicit inline ownership and short spin-guarded data. Runtime closure: std only.
/// Inline secret storage with explicit exposure, transfer and unconditional erasure.
pub const Secret = @import("Secret.zig").Secret;
/// Data beside its acquire/release spin lock; guards borrow until release.
pub const Guarded = @import("Guarded.zig").Guarded;
