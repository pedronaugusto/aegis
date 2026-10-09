//! Bounded inline public diagnostics. No allocation, borrowed causes or generic formatters.
const std = @import("std");
/// Explicit classification of runtime text. The reason is reviewed at the consumer site.
pub const PublicSource = struct {
    bytes: []const u8,
    pub fn classify(bytes: []const u8, comptime reason: []const u8) PublicSource {
        if (comptime std.mem.trim(u8, reason, " \t\r\n").len == 0) @compileError("public text classification requires a reason");
        return .{ .bytes = bytes };
    }
};
pub fn PublicText(comptime N: usize) type {
    return struct {
        const Self = @This();
        pub const public_text_capacity = N;
        bytes: [N]u8 = @splat(0),
        len: usize = 0,
        truncated: bool = false,
        pub fn literal(comptime label: []const u8) Self {
            return copy(.{ .bytes = label });
        }
        pub fn copy(source: PublicSource) Self {
            var result: Self = .{};
            const hex = "0123456789abcdef";
            for (source.bytes) |byte| {
                const escaped = byte < 0x20 or byte >= 0x7f or byte == '\\' or byte == '"';
                const count: usize = if (escaped) 4 else 1;
                if (count > N - result.len) {
                    result.truncated = true;
                    break;
                }
                if (escaped) {
                    @memcpy(result.bytes[result.len..][0..4], &[4]u8{ '\\', 'x', hex[byte >> 4], hex[byte & 15] });
                } else result.bytes[result.len] = byte;
                result.len += count;
            }
            return result;
        }
        pub fn view(self: *const Self) []const u8 {
            return self.bytes[0..@min(self.len, N)];
        }
    };
}
fn publicType(comptime T: type) void {
    switch (@typeInfo(T)) {
        .bool, .int => {},
        .@"enum" => {
            if (@hasDecl(T, "deinit") or @hasDecl(T, "format")) @compileError("Context requires a closed public frame");
        },
        .@"struct" => |s| {
            if (@hasDecl(T, "public_text_capacity") and T == PublicText(T.public_text_capacity)) return;
            if (@hasDecl(T, "deinit") or @hasDecl(T, "moveInto") or @hasDecl(T, "format") or !@hasDecl(T, "aegis_public_frame"))
                @compileError("Context requires a closed public frame with explicit admission, no owners or formatters");
            if (T.aegis_public_frame != true) @compileError("Context requires explicit public frame admission");
            for (s.field_names) |field| publicType(@FieldType(T, field));
        },
        else => @compileError("Context requires a closed public frame: pointers, slices, unions and unknown types are forbidden"),
    }
}
fn writePublic(comptime T: type, value: T, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (@typeInfo(T)) {
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .int => try writer.print("{d}", .{value}),
        .@"enum" => try writer.print("{d}", .{@backingInt(value)}),
        .@"struct" => |s| {
            if (comptime @hasDecl(T, "public_text_capacity") and T == PublicText(T.public_text_capacity)) {
                try writer.writeAll(value.view());
                if (value.truncated) try writer.writeAll("[truncated]");
            } else {
                inline for (s.field_names, 0..) |field, i| {
                    if (i != 0) try writer.writeAll(" ");
                    try writer.writeAll(field ++ "=");
                    try writePublic(@FieldType(T, field), @field(value, field), writer);
                }
            }
        },
        else => unreachable,
    }
}
pub fn Context(comptime Frame: type, comptime N: usize) type {
    comptime publicType(Frame);
    return struct {
        const Self = @This();
        buffer: [N]Frame = undefined,
        len: usize = 0,
        truncated: bool = false,
        pub fn push(self: *Self, frame: Frame) void {
            if (self.len >= N) {
                self.truncated = true;
                return;
            }
            self.buffer[self.len] = frame;
            self.len += 1;
        }
        pub fn reset(self: *Self) void {
            self.len = 0;
            self.truncated = false;
        }
        pub fn frames(self: *const Self) []const Frame {
            return self.buffer[0..@min(self.len, N)];
        }
        pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            for (self.frames(), 0..) |frame, i| {
                if (i != 0) try writer.writeAll("\n");
                try writePublic(Frame, frame, writer);
            }
            if (self.truncated) try writer.writeAll("\n[truncated]");
        }
    };
}
pub fn Failure(comptime ErrorSet: type, comptime Frame: type, comptime N: usize) type {
    if (@typeInfo(ErrorSet) != .error_set or ErrorSet == anyerror) @compileError("Failure requires a named error set");
    return struct { cause: ErrorSet, context: Context(Frame, N) = .{} };
}
