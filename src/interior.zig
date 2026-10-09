//! Whether a type declares that all of its mutation is behind its own lock.
/// True when `T` declares `pub const interior_lock = true`. The aegis guards declare it. A type
/// that owns its own synchronization may declare it too, to be shared through a mutable pointer.
pub fn locked(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "interior_lock") and T.interior_lock,
        else => false,
    };
}

/// The pointer a shared owner hands out: mutable only for a type that locks itself.
pub fn Handout(comptime T: type) type {
    return if (locked(T)) *T else *const T;
}
