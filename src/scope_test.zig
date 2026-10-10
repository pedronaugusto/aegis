const std = @import("std");
const builtin = @import("builtin");
const shake = @import("shakedown");
const a = @import("root.zig");
const scope = a.scope;
const t = std.testing;
const checked = builtin.optimize == .debug or builtin.optimize == .safe;

const Request = struct {};
const Connection = struct {};
const Requests = scope.Table(Request);
const Connections = scope.Table(Connection);

/// Whether a reference would pass its check now, read without stopping the program.
fn live(reference: anytype) bool {
    return !checked or reference.slot.generation.load(.monotonic) == reference.generation;
}

/// Outside Debug and ReleaseSafe nothing records that a scope ended, so nothing can be stale.
fn stale(reference: anytype) !void {
    if (checked) try t.expect(!live(reference));
}

test "A12 a reference gives back its pointer while its scope is open" {
    var storage: [2]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    var bytes: [4]u8 = .{ 1, 2, 3, 4 };
    var count: u32 = 9;
    const request = try table.open();
    const view = request.ref(bytes[0..]);
    const single = request.ref(&count);
    try t.expectEqual(@as(usize, 4), view.get().len);
    try t.expectEqual(@as(u8, 3), view.get()[2]);
    try t.expect(single.get() == &count);
    try t.expect(@TypeOf(single.get()) == *u32);
    const constant = request.ref(@as([]const u8, bytes[0..2]));
    try t.expect(@TypeOf(constant.get()) == []const u8);
    request.end();
}

test "A12 ending a scope moves its generation on and a reopened slot hands out the next" {
    var storage: [1]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    var value: u32 = 5;
    const first = try table.open();
    const old = first.ref(&value);
    try t.expect(live(old));
    first.end();
    try stale(old);
    const second = try table.open();
    const fresh = second.ref(&value);
    try t.expect(live(fresh));
    try stale(old);
    if (checked) try t.expectEqual(old.generation + 1, fresh.generation);
    second.end();
    try stale(fresh);
}

test "A12 scopes in different slots end independently" {
    var storage: [3]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    var value: u8 = 1;
    const one = try table.open();
    const two = try table.open();
    const three = try table.open();
    const r1 = one.ref(&value);
    const r2 = two.ref(&value);
    const r3 = three.ref(&value);
    two.end();
    try t.expect(live(r1) and live(r3));
    try stale(r2);
    one.end();
    three.end();
    try stale(r1);
    try stale(r3);
}

test "A12 a full table refuses only where scopes are tracked" {
    var storage: [2]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    const one = try table.open();
    const two = try table.open();
    if (checked) {
        try t.expectError(error.Full, table.open());
        one.end();
        const again = try table.open();
        try t.expectError(error.Full, table.open());
        again.end();
    } else {
        const three = try table.open();
        three.end();
        one.end();
    }
    two.end();
    var none: [0]Requests.Slot = undefined;
    var empty = Requests.init(&none);
    defer empty.deinit();
    if (checked) try t.expectError(error.Full, empty.open());
}

test "A12 a slot that used every generation retires and the table reports exhaustion" {
    if (!checked) return;
    var storage: [2]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    storage[0].generation.store(std.math.maxInt(u64) - 1, .monotonic);
    const last = try table.open(); // slot 0 hands out its last usable generation
    const other = try table.open();
    var value: u8 = 0;
    const view = last.ref(&value);
    last.end();
    try stale(view); // the generation after the last one is never handed out
    try t.expectEqual(@as(usize, 1), table.used_up);
    try t.expectError(error.Full, table.open()); // slot 1 is still open
    other.end();
    const only = try table.open();
    only.end();
    storage[1].generation.store(std.math.maxInt(u64) - 1, .monotonic);
    const retiring = try table.open();
    retiring.end();
    try t.expectError(error.Exhausted, table.open());
}

test "A12 brands are different types and a reborrow rebinds the reference" {
    comptime {
        std.debug.assert(scope.Ref(Request, *u32) != scope.Ref(Connection, *u32));
        std.debug.assert(scope.Ref(Request, *u32) == scope.Ref(Request, *u32));
        std.debug.assert(scope.Ref(Request, *u32).brand == Request);
        std.debug.assert(Requests.Scope != Connections.Scope);
    }
    var requests_storage: [1]Requests.Slot = undefined;
    var connections_storage: [1]Connections.Slot = undefined;
    var requests = Requests.init(&requests_storage);
    var connections = Connections.init(&connections_storage);
    defer requests.deinit();
    defer connections.deinit();
    var value: u32 = 11;
    const request = try requests.open();
    const connection = try connections.open();
    const short = request.ref(&value);
    const kept = connection.reborrow(short);
    try t.expect(@TypeOf(kept) == scope.Ref(Connection, *u32));
    request.end();
    try stale(short);
    try t.expect(live(kept));
    try t.expect(kept.get() == &value);
    connection.end();
}

test "A12 outside Debug and ReleaseSafe the scope machinery is gone" {
    if (checked) return;
    try t.expectEqual(@as(usize, 0), @sizeOf(Requests.Slot));
    try t.expectEqual(@as(usize, 0), @sizeOf(Requests));
    try t.expectEqual(@as(usize, 0), @sizeOf(Requests.Scope));
    try t.expectEqual(@sizeOf(*u32), @sizeOf(scope.Ref(Request, *u32)));
    try t.expectEqual(@sizeOf([]u8), @sizeOf(scope.Ref(Request, []u8)));
    try t.expectEqual(@alignOf(*u32), @alignOf(scope.Ref(Request, *u32)));
}

test "A12 checked layout is a pointer, the creator's record and a generation" {
    if (!checked) return;
    const Pointer = scope.Ref(Request, *u32);
    try t.expectEqual(@sizeOf(*u32) + @sizeOf(*const Requests.Slot) + @sizeOf(u64), @sizeOf(Pointer));
    try t.expectEqual(@as(usize, 16), @sizeOf(Requests.Slot));
}

const Model = struct {
    generation: [4]u64 = @splat(1),
    open: [4]bool = @splat(false),
};

const Held = struct { scope: Requests.Scope, slot: usize, generation: u64 };

fn trace(_: void, case: *shake.Case) anyerror!void {
    if (!checked) return;
    var storage: [4]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    var model: Model = .{};
    var held: [4]?Held = @splat(null);
    var refs: [16]struct { view: scope.Ref(Request, *u8), slot: usize, generation: u64 } = undefined;
    var made: usize = 0;
    var value: u8 = 0;
    for (0..96) |_| {
        switch (shake.gen.intRange(case.source, u8, 0, 2)) {
            0 => {
                const opened = table.open() catch |err| {
                    try t.expectEqual(error.Full, err);
                    continue;
                };
                const slot = opened.index;
                try t.expect(!model.open[slot]);
                model.open[slot] = true;
                held[slot] = .{ .scope = opened, .slot = slot, .generation = model.generation[slot] };
            },
            1 => {
                const pick = shake.gen.intRange(case.source, usize, 0, 3);
                const open = held[pick] orelse continue;
                open.scope.end();
                model.open[open.slot] = false;
                model.generation[open.slot] += 1;
                held[pick] = null;
            },
            else => {
                const pick = shake.gen.intRange(case.source, usize, 0, 3);
                const open = held[pick] orelse continue;
                if (made == refs.len) continue;
                refs[made] = .{ .view = open.scope.ref(&value), .slot = open.slot, .generation = open.generation };
                made += 1;
            },
        }
        for (refs[0..made]) |each| {
            const expected = model.open[each.slot] and model.generation[each.slot] == each.generation;
            try t.expectEqual(expected, live(each.view));
        }
    }
    for (held) |maybe| if (maybe) |open| open.scope.end();
    table.deinit();
}

test "A12 generated open, end and reference traces agree with a model of generations" {
    if (!checked) return;
    try shake.check(t.allocator, {}, trace, .{ .cases = 256, .seed = 0xa12 });
}

const Racer = struct {
    view: scope.Ref(Request, *u32),
    saw_end: std.atomic.Value(bool) = .init(false),
    fn watch(self: *Racer) void {
        var spins: usize = 0;
        while (live(self.view) and spins < 200_000_000) : (spins += 1) std.atomic.spinLoopHint();
        self.saw_end.store(!live(self.view), .release);
    }
};

test "A12 native a check that races the end of its scope reads the generation atomically" {
    if (builtin.single_threaded or !checked) return;
    var storage: [1]Requests.Slot = undefined;
    var table = Requests.init(&storage);
    defer table.deinit();
    var value: u32 = 3;
    const request = try table.open();
    var racer: Racer = .{ .view = request.ref(&value) };
    const thread: std.Thread = try .spawn(.{}, Racer.watch, .{&racer});
    request.end();
    thread.join();
    try t.expect(racer.saw_end.load(.acquire));
}
