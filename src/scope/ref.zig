//! A reference that remembers the scope it was made in.
const std = @import("std");
const slot = @import("slot.zig");
const checked = slot.checked;

fn pointerOf(comptime P: type) std.lang.Type.Pointer {
    const info = switch (@typeInfo(P)) {
        .pointer => |pointer| pointer,
        else => @compileError("scope.Ref wraps a single-item pointer or a slice"),
    };
    if (info.size != .one and info.size != .slice) @compileError("scope.Ref wraps a single-item pointer or a slice");
    return info;
}

/// A pointer or slice `P` made in a scope of brand `Brand`. Two brands never mix: a reference from one
/// is a different type from a reference from another, so the compiler rejects passing it where the
/// other is expected. In Debug and ReleaseSafe `get` also checks, on every use, that the scope has not
/// ended, and stops the program if it has. In ReleaseFast and ReleaseSmall the reference is exactly `P`.
///
/// This catches use after a scope ends when the reference is used; it proves nothing about a reference
/// that is never used, and nothing about a raw pointer taken out of `get` and kept.
pub fn Ref(comptime Brand: type, comptime P: type) type {
    _ = pointerOf(P);
    return struct {
        const Self = @This();
        /// The brand: the kind of scope this reference was made in.
        pub const brand = Brand;
        /// The pointer type `get` returns.
        pub const Pointer = P;
        /// Private: reach it through `get`.
        ptr: P,
        /// Private: the creator's record of the scope; checked builds only.
        slot: if (checked) *const slot.Slot else void,
        /// Private: the generation the scope had when this was made; checked builds only.
        generation: if (checked) u64 else void,

        /// The pointer, valid until the scope ends. Debug and ReleaseSafe stop the program if it already has.
        /// The raw pointer carries no check: use it now and do not keep it.
        pub fn get(self: *const Self) P {
            if (checked and self.slot.generation.load(.monotonic) != self.generation) @panic("scope reference used after its scope ended");
            return self.ptr;
        }
    };
}
