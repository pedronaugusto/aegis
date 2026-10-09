//! Correct handwritten operations paired with A8/A9 enclosing caller paths.
const std = @import("std");
const a = @import("aegis");
const Tag = struct {};
pub const Pool = a.handle.Pool(u32, Tag);
pub const Key = Pool.Key;
pub const Direct = struct {
    pub const Slot = struct { generation: u64 = 1, next: usize = std.math.maxInt(usize), state: enum { free, live, retired } = .free, value: u32 = undefined };
    slots: []Slot,
    instance: a.handle.Instance,
    free_head: usize,
    len: usize = 0,
    retired: usize = 0,
};
pub const Frame = struct {
    pub const aegis_public_frame = true;
    phase: u8,
    offset: u32,
    reason: u8,
};
pub const Context = a.err.Context(Frame, 4);
pub const DirectContext = struct { buffer: [4]Frame = undefined, len: usize = 0, truncated: bool = false };
pub const Parsed = struct { kind: u8, body: []const u8 };
pub const ParseError = error{ Truncated, LimitExceeded };
pub fn parse(limit: usize, bytes: []const u8) ParseError!Parsed {
    if (bytes.len < 2) return error.Truncated;
    if (bytes[1] > limit) return error.LimitExceeded;
    if (bytes[1] > bytes.len - 2) return error.Truncated;
    return .{ .kind = bytes[0], .body = bytes[2..][0..bytes[1]] };
}
comptime {
    std.debug.assert(@sizeOf(Pool) == @sizeOf(Direct));
    std.debug.assert(@alignOf(Pool) == @alignOf(Direct));
    std.debug.assert(@sizeOf(Pool.Slot) == @sizeOf(Direct.Slot));
    std.debug.assert(@alignOf(Pool.Slot) == @alignOf(Direct.Slot));
    std.debug.assert(@sizeOf(Context) == @sizeOf(DirectContext));
    std.debug.assert(@alignOf(Context) == @alignOf(DirectContext));
    std.debug.assert(@sizeOf(a.input.Untrusted([]const u8)) == @sizeOf([]const u8));
}
inline fn live(p: *const Direct, key: Key) bool {
    if (p.instance.namespace != key.instance.namespace or p.instance.serial != key.instance.serial or key.index >= p.slots.len) return false;
    const slot = &p.slots[key.index];
    return slot.state == .live and slot.generation == key.generation;
}
pub export fn baselineHandleGet(p: *const Direct, key: *const Key) u32 {
    if (!live(p, key.*)) return 0;
    return p.slots[key.index].value;
}
pub export fn wrapperHandleGet(p: *const Pool, key: *const Key) u32 {
    return (p.getConst(key.*) catch return 0).*;
}
inline fn overlap(value: *const u32, storage: anytype) bool {
    if (storage.len == 0) return false;
    const x = @intFromPtr(value); // safe: live source address for extent comparison
    const y = @intFromPtr(storage.ptr); // safe: live storage address
    const bytes = std.math.mul(usize, storage.len, @sizeOf(@typeInfo(@TypeOf(storage)).pointer.child)) catch return true;
    return if (x >= y) x - y < bytes else y - x < @sizeOf(u32);
}
inline fn alias(value: *const u32, p: *const Direct) bool {
    return overlap(value, @as([]const u8, std.mem.asBytes(p))) or overlap(value, p.slots);
}
inline fn insertDirect(p: *Direct, source: *u32) error{ AliasedStorage, Full }!Key {
    if (overlap(source, @as([]const u8, std.mem.asBytes(p)))) return error.AliasedStorage;
    const slots = p.slots;
    if (overlap(source, slots)) return error.AliasedStorage;
    if (p.free_head == std.math.maxInt(usize)) return error.Full;
    const i = p.free_head;
    const slot = &slots[i];
    p.free_head = slot.next;
    slot.value = source.*;
    source.* = undefined;
    slot.state = .live;
    p.len += 1;
    return .{ .instance = p.instance, .index = i, .generation = slot.generation };
}
pub export fn baselineHandleInsert(p: *Direct, source: *u32) u64 {
    return (insertDirect(p, source) catch return 0).generation;
}
pub export fn wrapperHandleInsert(p: *Pool, source: *u32) u64 {
    return (p.insert(source) catch return 0).generation;
}
inline fn removeDirect(p: *Direct, key: Key, out: *u32) error{ InvalidKey, AliasedStorage }!void {
    if (!live(p, key)) return error.InvalidKey;
    if (alias(out, p)) return error.AliasedStorage;
    const index = key.index;
    const slot = &p.slots[index];
    out.* = slot.value;
    slot.value = undefined;
    p.len -= 1;
    if (slot.generation == std.math.maxInt(u64)) {
        slot.state = .retired;
        p.retired += 1;
    } else {
        slot.generation += 1;
        slot.state = .free;
        slot.next = p.free_head;
        p.free_head = index;
    }
}
pub export fn baselineHandleRemove(p: *Direct, key: *const Key, out: *u32) bool {
    removeDirect(p, key.*, out) catch return false;
    return true;
}
pub export fn wrapperHandleRemove(p: *Pool, key: *const Key, out: *u32) bool {
    p.remove(key.*, out) catch return false;
    return true;
}
pub export fn baselineHandleIndex(raw: u32, values: [*]const u32, len: usize) u32 {
    if (raw >= len) return 0;
    return values[raw];
}
pub export fn wrapperHandleIndex(raw: u32, values: [*]const u32, len: usize) u32 {
    const i = a.handle.Index(Tag, u32).from(raw, len) catch return 0;
    return (i.get(values[0..len]) catch return 0).*;
}
pub export fn baselineInputParse(bytes: [*]const u8, len: usize, limit: usize) usize {
    const parsed = parse(limit, bytes[0..len]) catch return 0;
    return @as(usize, parsed.kind) + parsed.body.len;
}
pub export fn wrapperInputParse(bytes: [*]const u8, len: usize, limit: usize) usize {
    const parsed = a.input.Untrusted([]const u8).init(bytes[0..len]).parse(limit, parse) catch return 0;
    return @as(usize, parsed.kind) + parsed.body.len;
}
inline fn pushDirect(ctx: *DirectContext, frame: Frame) void {
    if (ctx.len >= 4) {
        ctx.truncated = true;
        return;
    }
    ctx.buffer[ctx.len] = frame;
    ctx.len += 1;
}
pub export fn baselineContextPush(ctx: *DirectContext, phase: u8, offset: u32, reason: u8) void {
    pushDirect(ctx, .{ .phase = phase, .offset = offset, .reason = reason });
}
pub export fn wrapperContextPush(ctx: *Context, phase: u8, offset: u32, reason: u8) void {
    ctx.push(.{ .phase = phase, .offset = offset, .reason = reason });
}
pub export fn baselineInputDiagnostics(bytes: [*]const u8, len: usize, limit: usize, ctx: ?*DirectContext) usize {
    const parsed = parse(limit, bytes[0..len]) catch {
        if (ctx) |c| pushDirect(c, .{ .phase = 1, .offset = 0, .reason = 2 });
        return 0;
    };
    return @as(usize, parsed.kind) + parsed.body.len;
}
pub export fn wrapperInputDiagnostics(bytes: [*]const u8, len: usize, limit: usize, ctx: ?*Context) usize {
    const parsed = a.input.Untrusted([]const u8).init(bytes[0..len]).parse(limit, parse) catch {
        if (ctx) |c| c.push(.{ .phase = 1, .offset = 0, .reason = 2 });
        return 0;
    };
    return @as(usize, parsed.kind) + parsed.body.len;
}
const Dense = a.handle.Dense(u32, Tag);
pub export fn baselineDenseSum(values: [*]const u32, len: usize) u32 {
    var sum: u32 = 0;
    for (values[0..len]) |v| sum +%= v;
    return sum;
}
pub export fn wrapperDenseSum(values: [*]const u32, len: usize) u32 {
    // The owner descriptor is borrowed only for its live dense prefix.
    var d: Dense = undefined;
    d.values = @constCast(values[0..len]); // safe: only itemsConst is used; never writes
    d.used = len;
    var sum: u32 = 0;
    for (d.itemsConst()) |v| sum +%= v;
    return sum;
}
