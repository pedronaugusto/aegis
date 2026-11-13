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
        aegis_material: T,

        /// Initializes by value; caller/parser temporaries still need their own erasure.
        pub fn init(value: T) Self {
            return .{ .aegis_material = value };
        }

        /// Makes the material in this owner's own storage: `maker`'s result, called with `args`, is
        /// written straight into the owner's field (its result location), so no copy of it lands in
        /// the caller's frame, as one does when `init` takes a value. Copies inside `maker` itself (a
        /// std generator's locals, its own return) are the maker's and out of reach: `make`
        /// guarantees only that the caller holds none. The owner holds no live material before:
        /// declare it `undefined`, or call it after `deinit`. A maker that can fail
        /// (`KeyPair.generateDeterministic(seed)`) makes `make` fail with its errors: its result is
        /// held in this function's frame and erased before it returns, and on an error the owner
        /// holds none (its storage erased).
        pub fn make(self: *Self, comptime maker: anytype, args: anytype) Made(maker) {
            if (comptime Made(maker) == void) {
                self.aegis_material = @call(.auto, maker, args);
                return;
            }
            var made = @call(.auto, maker, args);
            defer std.crypto.secureZero(u8, std.mem.asBytes(&made));
            self.aegis_material = made catch |err| {
                self.deinit();
                return err;
            };
        }

        /// Borrows until transfer or cleanup. Do not retain or return this pointer.
        pub fn expose(self: *const Self) *const T {
            return &self.aegis_material;
        }

        /// Borrows until transfer or cleanup. Erase displaced bytes before replacement.
        pub fn exposeMut(self: *Self) *T {
            return &self.aegis_material;
        }

        /// Transfers into uninitialized, disjoint storage and erases the source.
        /// Consumes self; all source borrows end. Never overwrite a live destination.
        pub fn moveInto(self: *Self, destination: *Self) void {
            @setRuntimeSafety(true);
            @memcpy(std.mem.asBytes(&destination.aegis_material), std.mem.asBytes(&self.aegis_material));
            self.deinit();
        }

        /// Erases every representation byte, including padding, in every build mode.
        /// Consumes self. The erased bytes need not represent a valid T; no typed reads afterward.
        /// No destructor/allocator is invoked and there is no automatic cleanup on abort.
        pub fn deinit(self: *Self) void {
            std.crypto.secureZero(u8, std.mem.asBytes(&self.aegis_material));
        }

        /// Fails closed without writing secret bytes. Exposure/reflection can bypass it.
        pub fn format(_: *const Self, _: *std.Io.Writer) error{SecretNotFormattable}!void {
            return error.SecretNotFormattable;
        }
    };
}

/// What `Secret.make` returns for `maker`: nothing for a maker that cannot fail, its errors for
/// one whose result is an error union.
fn Made(comptime maker: anytype) type {
    const Result = @typeInfo(@TypeOf(maker)).@"fn".return_type.?;
    return switch (@typeInfo(Result)) {
        .error_union => |info| info.error_set!void,
        else => void,
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
