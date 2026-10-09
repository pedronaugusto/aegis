//! Independently importable secret owners and audited value kernels.
pub const Secret = @import("secret/inline.zig").Secret;
pub const SecretBytes = @import("secret/SecretBytes.zig");
const value = @import("secret/value.zig");
pub const Choice = value.Choice;
pub const OrderChoices = value.OrderChoices;
pub const CompareError = value.CompareError;
pub const SelectError = value.SelectError;
pub const equal = value.equal;
pub const equalBytes = value.equalBytes;
pub const compareUnsigned = value.compareUnsigned;
