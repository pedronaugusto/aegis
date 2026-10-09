//! Boundary marker and parser adaptation; parsing conveys no authority or ownership.
const std = @import("std");
fn View(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            var attrs = p.attrs;
            attrs.@"const" = true;
            break :blk @Pointer(p.size, attrs, p.child, p.sentinel());
        },
        else => T,
    };
}
fn nonowning(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (@hasDecl(T, "deinit") or @hasDecl(T, "moveInto")) @compileError("Untrusted requires nonowning by-value input; borrow an owner explicitly");
            for (s.field_names) |field| nonowning(@FieldType(T, field));
        },
        .@"union" => |u| {
            if (@hasDecl(T, "deinit") or @hasDecl(T, "moveInto")) @compileError("Untrusted requires nonowning by-value input");
            for (u.field_names) |field| nonowning(@FieldType(T, field));
        },
        .array => |a| nonowning(a.child),
        .optional => |o| nonowning(o.child),
        .error_union => |e| nonowning(e.payload),
        else => {},
    }
}
pub fn Untrusted(comptime T: type) type {
    comptime nonowning(T);
    return struct {
        const Self = @This();
        pub const aegis_untrusted = true;
        value: View(T),
        pub fn init(value: T) Self {
            return .{ .value = value };
        }
        pub inline fn readForParse(self: Self) View(T) {
            return self.value;
        }
        pub inline fn parse(self: Self, context: anytype, comptime parser: anytype) Result(parser) {
            return parser(context, self.readForParse());
        }
        fn Result(comptime parser: anytype) type {
            const info = @typeInfo(@TypeOf(parser));
            if (info != .@"fn" or info.@"fn".return_type == null) @compileError("Untrusted parser requires an explicit named error union and refined result");
            const R = info.@"fn".return_type.?;
            if (@typeInfo(R) != .error_union) @compileError("Untrusted parser requires an explicit named error union and refined result");
            const e = @typeInfo(R).error_union;
            if (e.error_set == anyerror or e.payload == bool or e.payload == Self or e.payload == T or e.payload == View(T) or e.payload == void)
                @compileError("Untrusted parser must return a distinct refined result with a named error set");
            switch (@typeInfo(e.payload)) {
                .@"struct", .@"union", .@"enum", .@"opaque" => if (@hasDecl(e.payload, "aegis_untrusted")) @compileError("Untrusted parser must return a distinct refined result"),
                else => {},
            }
            return R;
        }
    };
}
