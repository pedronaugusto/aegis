const std = @import("std");
const parts = @import("parts.zig");
const t = std.testing;

const State = struct { a: u64, b: [3]u32 };
const Sequence = extern struct { lit: u32, len: u16, off: u16 };

// A compressor's shape: matchfinders of which one is in use at a time, an optional parser state,
// the sequences and literals, inside a stream with its window and pending output.
const Chains = struct { prev: []u32, hash4: []u32, hash3: []u32 };
const Table = struct { table: [][2]u32 };
const Finders = struct {
    pub const arrangement: parts.Arrangement = .overlap;
    chains: ?Chains,
    table: ?Table,
};
const Engine = struct { finders: Finders, state: ?*State, seqs: []Sequence, lits: []u8 };
const Stream = struct { engine: Engine, window: []align(64) u8, pending: []u8, header: *[10]u8 };

const stream_counts: parts.Block(Stream).Counts = .{
    .engine = .{
        .finders = .{ .chains = .{ .prev = 1 << 10, .hash4 = 1 << 9, .hash3 = 1 << 8 }, .table = .{ .table = 1 << 9 } },
        .state = true,
        .seqs = 100,
        .lits = 333,
    },
    .window = 1 << 12,
    .pending = 77,
};

fn span(slice: anytype) [2]usize {
    // The part's own pointer: sliceAsBytes gives an empty slice a static one.
    const start = @intFromPtr(slice.ptr);
    return .{ start, start + std.mem.sliceAsBytes(slice).len };
}

fn inside(s: [2]usize, block: []const u8) bool {
    return s[0] >= @intFromPtr(block.ptr) and s[1] <= @intFromPtr(block.ptr) + block.len;
}

fn disjoint(a: [2]usize, b: [2]usize) bool {
    return a[1] <= b[0] or b[1] <= a[0];
}

test "parts: a plan's size is the measure of its parts, each at its alignment" {
    const B = parts.Block(Stream);
    try t.expectEqual(@as(usize, 64), B.alignment);
    const plan = B.plan(stream_counts);
    // Chains 4 KiB + 2 KiB + 1 KiB overlap the 4 KiB table: 7 KiB; the state; the sequences and
    // literals; the window at 64; the pending bytes and the header.
    var at: usize = 7 << 10;
    at = std.mem.alignForward(usize, at, @alignOf(State)) + @sizeOf(State);
    at = std.mem.alignForward(usize, at, @alignOf(Sequence)) + 100 * @sizeOf(Sequence);
    at += 333;
    at = std.mem.alignForward(usize, at, 64) + (1 << 12);
    at += 77 + 10;
    try t.expectEqual(at, (try plan.size()).raw());
}

test "parts: every part lies in the block, aligned, apart from the others but its alternatives" {
    const B = parts.Block(Stream);
    const block = try B.plan(stream_counts).alloc(t.allocator);
    defer t.allocator.free(block.bytes());
    const p = block.parts();
    const memory = block.bytes();

    const chains = p.engine.finders.chains.?;
    const table = p.engine.finders.table.?;
    try t.expectEqual(@intFromPtr(chains.prev.ptr), @intFromPtr(table.table.ptr));
    try t.expectEqual(@intFromPtr(memory.ptr), @intFromPtr(chains.prev.ptr));
    try t.expectEqual(@as(usize, 1 << 10), chains.prev.len);
    try t.expectEqual(@as(usize, 1 << 9), table.table.len);
    try t.expectEqual(@as(usize, 0), @intFromPtr(p.window.ptr) % 64);

    const sequence = [_][2]usize{
        span(chains.prev),                       span(chains.hash4),  span(chains.hash3),
        span(std.mem.asBytes(p.engine.state.?)), span(p.engine.seqs), span(p.engine.lits),
        span(p.window),                          span(p.pending),     span(p.header),
    };
    const finders_end = @max(span(chains.hash3)[1], span(table.table)[1]);
    for (sequence, 0..) |a, i| {
        try t.expect(inside(a, memory));
        for (sequence[i + 1 ..]) |b| try t.expect(disjoint(a, b));
        if (i >= 3) try t.expect(a[0] >= finders_end);
    }
    try t.expect(inside(span(table.table), memory));
    try t.expectEqual(@as(usize, 0), @intFromPtr(p.engine.state.?) % @alignOf(State));
    try t.expectEqual(@as(usize, 0), @intFromPtr(p.engine.seqs.ptr) % @alignOf(Sequence));

    // Each part keeps what is written to it.
    @memset(chains.prev, 1);
    @memset(chains.hash4, 2);
    @memset(chains.hash3, 3);
    p.engine.state.?.* = .{ .a = 4, .b = .{ 4, 4, 4 } };
    @memset(p.engine.seqs, .{ .lit = 5, .len = 5, .off = 5 });
    @memset(p.engine.lits, 6);
    @memset(p.window, 7);
    @memset(p.pending, 8);
    @memset(p.header, 9);
    for (chains.prev) |v| try t.expectEqual(@as(u32, 1), v);
    for (chains.hash3) |v| try t.expectEqual(@as(u32, 3), v);
    try t.expectEqual(@as(u64, 4), p.engine.state.?.a);
    for (p.engine.lits) |v| try t.expectEqual(@as(u8, 6), v);
    for (p.pending) |v| try t.expectEqual(@as(u8, 8), v);
}

test "parts: an absent part takes no bytes and is null" {
    const B = parts.Block(Stream);
    var counts = stream_counts;
    counts.engine.state = false;
    counts.engine.finders.chains = null;
    const with = (try B.plan(stream_counts).size()).raw();
    const without = (try B.plan(counts).size()).raw();
    try t.expect(without < with);
    const block = try B.plan(counts).alloc(t.allocator);
    defer t.allocator.free(block.bytes());
    const p = block.parts();
    try t.expect(p.engine.state == null);
    try t.expect(p.engine.finders.chains == null);
    try t.expectEqual(@as(usize, 1 << 9), p.engine.finders.table.?.table.len);
}

test "parts: fit takes a buffer of the plan's size or longer and refuses a shorter one" {
    const B = parts.Block(Stream);
    const plan = B.plan(stream_counts);
    const n = (try plan.size()).raw();
    const buffer = try t.allocator.alignedAlloc(u8, .@"64", n + 64);
    defer t.allocator.free(buffer);
    try t.expectError(error.BufferTooSmall, plan.fit(buffer[0 .. n - 1]));
    const exact = try plan.fit(buffer[0..n]);
    try t.expectEqual(n, exact.bytes().len);
    const longer = try plan.fit(buffer);
    try t.expectEqual(n, longer.bytes().len);
    // The same counts place the same parts at the same offsets in any block.
    const p = longer.parts();
    const own = try plan.alloc(t.allocator);
    defer t.allocator.free(own.bytes());
    const q = own.parts();
    try t.expectEqual(@intFromPtr(p.pending.ptr) - @intFromPtr(buffer.ptr), @intFromPtr(q.pending.ptr) - @intFromPtr(own.bytes().ptr));
}

test "parts: counts past the address space are Overflow, and no block holds them" {
    const B = parts.Block(struct { a: []u64, b: []u8 });
    const plan = B.plan(.{ .a = std.math.maxInt(usize) / 4, .b = 1 });
    try t.expectError(error.Overflow, plan.size());
    try t.expectError(error.OutOfMemory, plan.alloc(t.allocator));
    var buffer: [64]u8 align(8) = undefined;
    try t.expectError(error.BufferTooSmall, plan.fit(&buffer));
    // Saturation holds wherever the overflow happens: in a count, an alignment or a sum.
    try t.expectError(error.Overflow, B.plan(.{ .a = 1, .b = std.math.maxInt(usize) }).size());
    try t.expectError(error.Overflow, B.plan(.{ .a = std.math.maxInt(usize) / 8, .b = 9 }).size());
}

const Worker = struct { engine: Engine, input: []align(64) u8, output: []align(64) u8 };
const Pool = struct { history: []u8, workers: parts.Repeat(Worker), records: []u64 };

test "parts: a Repeat's copies lie one after another at a stride, each placed as the counts say" {
    const B = parts.Block(Pool);
    const each: parts.Block(Worker).Counts = .{
        .engine = .{ .finders = .{ .chains = null, .table = .{ .table = 100 } }, .state = false, .seqs = 9, .lits = 10 },
        .input = 1000,
        .output = 1100,
    };
    const block = try B.plan(.{ .history = 32768, .workers = .{ .len = 5, .each = each }, .records = 5 }).alloc(t.allocator);
    defer t.allocator.free(block.bytes());
    const p = block.parts();
    try t.expectEqual(@as(usize, 5), p.workers.len());
    const one = (try parts.Block(Worker).plan(each).size()).raw();
    var spans: [5][2]usize = undefined;
    for (0..5) |i| {
        const w = p.workers.at(i);
        try t.expectEqual(@as(usize, 0), @intFromPtr(w.input.ptr) % 64);
        try t.expectEqual(@as(usize, 1100), w.output.len);
        try t.expect(w.engine.state == null);
        spans[i] = .{ @intFromPtr(w.engine.finders.table.?.table.ptr), @intFromPtr(w.output.ptr) + w.output.len };
        try t.expect(spans[i][1] - spans[i][0] <= one);
        try t.expect(inside(spans[i], block.bytes()));
        try t.expect(disjoint(spans[i], span(p.history)));
        try t.expect(disjoint(spans[i], span(p.records)));
        for (spans[0..i]) |s| try t.expect(disjoint(s, spans[i]));
        if (i > 0) try t.expectEqual(spans[i][0] - spans[i - 1][0], std.mem.alignForward(usize, one, 64));
    }
}

test "parts: generated counts always place every part inside its block, apart and aligned" {
    const Mixed = struct {
        small: []u8,
        one: *u16,
        maybe: ?[]u64,
        nested: struct { a: []u32, b: ?*[3]u8, c: []align(32) u8 },
        many: parts.Repeat(struct { x: []u16, y: []u8 }),
        last: []u8,
    };
    const B = parts.Block(Mixed);
    var prng: std.Random.DefaultPrng = .init(0x9a7c);
    const random = prng.random();
    for (0..2000) |_| {
        const counts: B.Counts = .{
            .small = random.uintLessThan(usize, 50),
            .maybe = if (random.boolean()) random.uintLessThan(usize, 40) else null,
            .nested = .{ .a = random.uintLessThan(usize, 30), .b = random.boolean(), .c = random.uintLessThan(usize, 70) },
            .many = .{ .len = random.uintLessThan(usize, 6), .each = .{ .x = random.uintLessThan(usize, 20), .y = random.uintLessThan(usize, 20) } },
            .last = random.uintLessThan(usize, 9),
        };
        const plan = B.plan(counts);
        const buffer = try t.allocator.alignedAlloc(u8, .@"32", (try plan.size()).raw());
        defer t.allocator.free(buffer);
        const p = (try plan.fit(buffer)).parts();
        var spans: [64][2]usize = undefined;
        var n: usize = 0;
        spans[n] = span(p.small);
        n += 1;
        spans[n] = span(std.mem.asBytes(p.one));
        n += 1;
        if (p.maybe) |m| {
            try t.expectEqual(counts.maybe.?, m.len);
            try t.expectEqual(@as(usize, 0), @intFromPtr(m.ptr) % 8);
            spans[n] = span(m);
            n += 1;
        } else try t.expect(counts.maybe == null);
        spans[n] = span(p.nested.a);
        n += 1;
        if (p.nested.b) |b| {
            spans[n] = span(b);
            n += 1;
        }
        try t.expectEqual(counts.nested.b, p.nested.b != null);
        try t.expectEqual(@as(usize, 0), @intFromPtr(p.nested.c.ptr) % 32);
        spans[n] = span(p.nested.c);
        n += 1;
        for (0..p.many.len()) |i| {
            const e = p.many.at(i);
            try t.expectEqual(counts.many.each.x, e.x.len);
            spans[n] = span(e.x);
            n += 1;
            spans[n] = span(e.y);
            n += 1;
        }
        spans[n] = span(p.last);
        n += 1;
        for (spans[0..n], 0..) |a, i| {
            try t.expect(inside(a, buffer));
            for (spans[i + 1 .. n]) |b| try t.expect(disjoint(a, b));
        }
    }
}

test "parts: a nested struct's counts are the counts its parent holds for it" {
    try t.expect(parts.Counts(Engine) == @FieldType(parts.Block(Stream).Counts, "engine"));
    try t.expect(parts.Counts(Stream) == parts.Block(Stream).Counts);
    const engine: parts.Counts(Engine) = stream_counts.engine;
    try t.expectEqual(@as(usize, 100), engine.seqs);
}

fn Tables(comptime pairs: bool) type {
    return struct { hash2: if (pairs) []u32 else void, hash4: []u32 };
}

test "parts: a part absent at compile time takes no bytes and no count" {
    const With = parts.Block(Tables(true));
    const Without = parts.Block(Tables(false));
    const with = With.plan(.{ .hash2 = 1024, .hash4 = 16 });
    const without = Without.plan(.{ .hash4 = 16 });
    try t.expectEqual(@as(usize, 1040 * 4), (try with.size()).raw());
    try t.expectEqual(@as(usize, 16 * 4), (try without.size()).raw());
    const block = try without.alloc(t.allocator);
    defer t.allocator.free(block.bytes());
    const p = block.parts();
    try t.expectEqual(@as(usize, 16), p.hash4.len);
    try t.expectEqual({}, p.hash2);
}

test "parts: a Given value comes back with the parts, so an optional nest carries what decided it" {
    const Dictionary = struct { bytes: parts.Given([]const u8), table: *[16]u32 };
    const B = parts.Block(struct { table: *[16]u32, dictionary: ?Dictionary });
    const text = "dictionary bytes";
    for ([_]?[]const u8{ text, null }) |given| {
        const counts: B.Counts = .{ .dictionary = if (given) |bytes| .{ .bytes = bytes } else null };
        const block = try B.plan(counts).alloc(t.allocator);
        defer t.allocator.free(block.bytes());
        // A Given takes no bytes: the block is one or two tables.
        try t.expectEqual(@as(usize, if (given != null) 128 else 64), block.bytes().len);
        const p = block.parts();
        if (p.dictionary) |d| {
            try t.expectEqualStrings(text, d.bytes.value);
            try t.expect(disjoint(span(std.mem.asBytes(d.table)), span(std.mem.asBytes(p.table))));
        } else try t.expect(given == null);
    }
}

test "parts: overlap alternatives of integers, floats, arrays, vectors and extern structs share their start" {
    const Pair = extern struct { a: u32, b: f32 };
    const Shared = struct {
        pub const arrangement: parts.Arrangement = .overlap;
        words: []u64,
        pairs: ?struct { pairs: []Pair, lanes: []@Vector(4, u32) },
        rows: [][3][2]u16,
    };
    const B = parts.Block(struct { shared: Shared });
    const block = try B.plan(.{ .shared = .{ .words = 4, .pairs = .{ .pairs = 2, .lanes = 1 }, .rows = 3 } }).alloc(t.allocator);
    defer t.allocator.free(block.bytes());
    const p = block.parts().shared;
    try t.expectEqual(@intFromPtr(p.words.ptr), @intFromPtr(p.pairs.?.pairs.ptr));
    try t.expectEqual(@intFromPtr(p.words.ptr), @intFromPtr(p.rows.ptr));
    // Written as one alternative, read as another: a value either way.
    @memset(p.words, 0x3f80_0000_3f80_0000);
    try t.expectEqual(@as(f32, 1.0), p.pairs.?.pairs[0].b);
}
