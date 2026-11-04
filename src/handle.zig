//! Slots, keys and positions on regions: storage never moves, so a value's pointer stays valid
//! until it is removed or its pool ends. Stable keys are checked; positions are only branded.
pub const Domain = @import("handle/Domain.zig");
pub const Instance = Domain.Instance;
pub const Index = @import("handle/index.zig").Index;
pub const OptionalIndex = @import("handle/index.zig").OptionalIndex;
pub const Offset = @import("handle/offset.zig").Offset;
pub const SlotPool = @import("handle/slot_pool.zig").SlotPool;
pub const SlotOptions = @import("handle/slot_pool.zig").Options;
pub const RunPool = @import("handle/run_pool.zig").RunPool;
pub const DenseSlotMap = @import("handle/dense.zig").DenseSlotMap;
pub const SecondaryMap = @import("handle/secondary.zig").SecondaryMap;
