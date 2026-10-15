//! Independently importable secret owners and audited value kernels.
pub const Secret = @import("secret/inline.zig").Secret;
pub const SecretBytes = @import("secret/SecretBytes.zig");
const value = @import("secret/value.zig");
pub const Choice = value.Choice;
/// The builds whose Choice lowering `zig build check-choices` inspects (`Choice.audited`).
pub const audited_profiles = @import("secret/profiles.zig");
pub const OrderChoices = value.OrderChoices;
pub const CompareError = value.CompareError;
pub const SelectError = value.SelectError;
pub const equal = value.equal;
pub const equalBytes = value.equalBytes;
pub const compareUnsigned = value.compareUnsigned;
const machine = @import("secret/machine.zig");
pub const scrubStack = machine.scrubStack;
pub const stackReach = machine.stackReach;
pub const scrubbed = machine.scrubbed;
pub const Timing = machine.Timing;
