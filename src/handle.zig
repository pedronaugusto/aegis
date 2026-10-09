//! Generational storage and checked positions. Stable keys are not stable pointers.
pub const Domain = @import("handle/Domain.zig");
pub const Instance = Domain.Instance;
pub const Index = @import("handle/index.zig").Index;
pub const typedIndex = Index;
pub const Pool = @import("handle/pool.zig").Pool;
pub const SlotMap = @import("handle/slot_map.zig").SlotMap;
pub const DenseSlotMap = @import("handle/dense.zig").DenseSlotMap;
pub const Dense = DenseSlotMap;
pub const SecondaryMap = @import("handle/secondary.zig").SecondaryMap;
