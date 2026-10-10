//! Scope lifetimes: a brand and a generation that catch a reference used after its scope ended.
/// One scope's record, kept by the creator's table.
pub const Slot = @import("scope/slot.zig").Slot;
/// The creator's table of scopes of one brand.
pub const Table = @import("scope/table.zig").Table;
/// A reference made in a scope of one brand.
pub const Ref = @import("scope/ref.zig").Ref;
