//! Fixed inline secret material. Copies and borrow endpoints are caller contracts.
const std = @import("std");

/// Owns pointer-free inline material. Pair initialization immediately with defer/errdefer.
/// Zig permits copies and reflective field access: this is not a linear type or borrow checker.
/// Wiping covers this storage only, not earlier copies, registers, spills, paging or aborts.
pub fn Secret(comptime T: type) type {
    comptime validate(T);
    return struct {
        const Self = @This();
        /// Private: access only through expose/exposeMut; never copy a live owner.
        material: T,

        /// Initializes by value; caller/parser temporaries still need their own erasure.
        pub fn init(value: T) Self {
            return .{ .material = value };
        }

        /// Borrows until transfer or cleanup. Do not retain or return this pointer.
        pub fn expose(self: *const Self) *const T {
            return &self.material;
        }

        /// Borrows until transfer or cleanup. Erase displaced bytes before replacement.
        pub fn exposeMut(self: *Self) *T {
            return &self.material;
        }

        /// Transfers into uninitialized, disjoint storage and erases the source.
        /// Consumes self; all source borrows end. Never overwrite a live destination.
        pub fn moveInto(self: *Self, destination: *Self) void {
            @setRuntimeSafety(true);
            @memcpy(std.mem.asBytes(&destination.material), std.mem.asBytes(&self.material));
            self.deinit();
        }

        /// Erases every representation byte, including padding, in every build mode.
        /// Consumes self. The erased bytes need not represent a valid T; no typed reads afterward.
        /// No destructor/allocator is invoked and there is no automatic cleanup on abort.
        pub fn deinit(self: *Self) void {
            std.crypto.secureZero(u8, std.mem.asBytes(&self.material));
        }

        /// Fails closed without writing secret bytes. Exposure/reflection can bypass it.
        pub fn format(_: *const Self, _: *std.Io.Writer) error{SecretNotFormattable}!void {
            return error.SecretNotFormattable;
        }
    };
}

fn validate(comptime T: type) void {
    switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum", .error_set, .void => {},
        .array => |info| validate(info.child),
        .vector => |info| validate(info.child),
        .optional => |info| validate(info.child),
        .error_union => |info| validate(info.payload),
        .@"struct" => |info| {
            if (@hasDecl(T, "deinit")) @compileError("Secret requires inline material without resource cleanup");
            for (info.field_names) |field| validate(@FieldType(T, field));
        },
        .@"union" => |info| {
            if (@hasDecl(T, "deinit")) @compileError("Secret requires inline material without resource cleanup");
            for (info.field_names) |field| validate(@FieldType(T, field));
        },
        else => @compileError("Secret requires pointer-free fixed inline material"),
    }
}

test {
    _ = @import("Secret_test.zig");
}
