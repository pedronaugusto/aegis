//! Runs of one type on a region of their own: a run is a start and a length, its items contiguous
//! and never moved while it lives. A freed run returns to the pool, coalesced with its free
//! neighbours, never to the system until the pool ends. Allocation is first fit in index order,
//! else growth at the end, as Goose's slice pool does; the free spans live in a B+ tree of
//! 512-byte nodes augmented with each subtree's longest span, so a fit is found in a walk from the
//! root.
const std = @import("std");
const Region = @import("../Region.zig");
const Index = @import("index.zig").Index;
const SlotPool = @import("slot_pool.zig").SlotPool;
const assert = @import("../assert.zig");

pub fn RunPool(comptime T: type, comptime Tag: type) type {
    return struct {
        const Self = @This();
        pub const Run = struct {
            start: Index(Tag, u32),
            len: u32,
        };
        pub const Error = Region.Error;

        /// Private: the region the items grow on.
        region: Region,
        /// Private: the first item.
        items: [*]T,
        /// Private: the items pushed so far; every run and free span lies below it.
        end: u32 = 0,
        /// Private: the free spans below `end`.
        free_spans: Spans,
        /// Private: the runs holding items. Free spans are separated by them, so there are never
        /// more spans than runs, which bounds the tree a free may need.
        runs: u32 = 0,

        /// The pool owns both regions from here on: `items` for the runs, `nodes` for the free
        /// spans' tree.
        pub fn init(items: Region, nodes: Region) Self {
            return .{
                .region = items,
                .items = @ptrFromInt(std.mem.alignForward(usize, items.top, @alignOf(T))), // safe: the items start at the region's top, aligned as its pushes align them
                .free_spans = .{ .nodes = .init(nodes) },
            };
        }
        /// Returns both regions; values in the runs are the caller's to have cleaned.
        pub fn deinit(p: *Self) void {
            p.free_spans.nodes.deinit();
            p.region.deinit();
            p.* = undefined;
        }
        /// `n` items, uninitialized: the first free span that holds them, in index order, else room
        /// at the end. No free span ends the pool: a free that would make one moves the end back.
        pub fn alloc(p: *Self, n: u32) Error!Run {
            if (n == 0) return .{ .start = @fromBackingInt(0), .len = 0 };
            // Every node the tree can need once this run exists, so no free ever fails.
            try p.free_spans.reserve(p.runs + 1);
            defer p.runs += 1;
            if (p.free_spans.firstFit(n)) |span| {
                if (span.len == n) p.free_spans.remove(span.start) else p.free_spans.set(span.start, span.start + n, span.len - n);
                return .{ .start = @fromBackingInt(span.start), .len = n };
            }
            const start = p.end;
            try p.grow(n);
            return .{ .start = @fromBackingInt(start), .len = n };
        }
        fn grow(p: *Self, n: u32) Error!void {
            const end = std.math.add(u32, p.end, n) catch return error.LimitExceeded;
            _ = try p.region.push(T, n);
            p.end = end;
        }
        /// The run at `n` items: in place when it shrinks, when the span after it is free and
        /// long enough, or when it ends the pool; else a new run with the items copied and the old
        /// one freed.
        pub fn realloc(p: *Self, run: Run, n: u32) Error!Run {
            p.check(run);
            if (run.len == 0) return p.alloc(n);
            if (n == 0) {
                p.free(run);
                return .{ .start = @fromBackingInt(0), .len = 0 };
            }
            const start = run.start.raw();
            if (n <= run.len) {
                p.release(start + n, run.len - n);
                return .{ .start = run.start, .len = n };
            }
            const more = n - run.len;
            const after = start + run.len;
            if (after == p.end) {
                try p.grow(more);
                return .{ .start = run.start, .len = n };
            }
            if (p.free_spans.atOrAfter(after)) |next| if (next.start == after and next.len >= more) {
                if (next.len == more) p.free_spans.remove(next.start) else p.free_spans.set(next.start, next.start + more, next.len - more);
                return .{ .start = run.start, .len = n };
            };
            const moved = try p.alloc(n);
            @memcpy(p.slice(moved)[0..run.len], p.slice(run));
            p.free(run);
            return moved;
        }
        /// Returns the run's items to the pool, joined with free neighbours. A run outside the
        /// pool, or one overlapping a free span (freed twice), stops in every build.
        pub fn free(p: *Self, run: Run) void {
            p.check(run);
            if (run.len == 0) return;
            p.release(run.start.raw(), run.len);
            p.runs -= 1;
        }
        fn release(p: *Self, start: u32, len: u32) void {
            if (len == 0) return;
            const spans = &p.free_spans;
            var merged: Span = .{ .start = start, .len = len };
            const before = if (start == 0) null else spans.below(start);
            const after = spans.atOrAfter(start);
            if (before) |b| assert.invariant(b.start + b.len <= start, "run freed twice or overlapping a free run");
            if (after) |a| assert.invariant(start + len <= a.start, "run freed twice or overlapping a free run");
            const joins_before = if (before) |b| b.start + b.len == start else false;
            if (after) |a| if (start + len == a.start) {
                spans.remove(a.start);
                merged.len += a.len;
            };
            if (joins_before) {
                const b = before.?;
                merged = .{ .start = b.start, .len = b.len + merged.len };
            }
            if (merged.start + merged.len == p.end) {
                // The pool's last items: the end comes back to the span's start.
                if (joins_before) spans.remove(merged.start);
                p.end = merged.start;
                p.region.top = @intFromPtr(p.items + merged.start);
            } else if (joins_before) {
                spans.set(merged.start, merged.start, merged.len);
            } else {
                spans.insert(merged);
            }
        }
        fn check(p: *const Self, run: Run) void {
            assert.invariant(run.len <= p.end and run.start.raw() <= p.end - run.len, "run outside its pool");
        }
        /// The run's items, valid until it is freed or the pool ends, whatever else is allocated.
        pub fn slice(p: *const Self, run: Run) []T {
            p.check(run);
            return p.items[run.start.raw()..][0..run.len];
        }
        /// Every run back at once, pages kept committed; every earlier run is outside the pool.
        pub fn recycleAll(p: *Self) void {
            p.free_spans.clear();
            p.end = 0;
            p.runs = 0;
            p.region.top = @intFromPtr(p.items);
        }
        /// The items in runs: pushed and not free.
        pub fn used(p: *const Self) usize {
            return p.end - p.free_spans.total;
        }
    };
}

/// A free span: `len` items from `start`.
const Span = struct { start: u32, len: u32 };

/// The free spans, ordered by start, in a B+ tree whose entries carry the longest span below
/// them. A node's keys are lower bounds of its children's starts, so a span may move its start up
/// in place.
const Spans = struct {
    nodes: Nodes,
    root: u32 = none,
    height: u32 = 0,
    /// The items in free spans.
    total: u32 = 0,

    const none = std.math.maxInt(u32);
    const fanout = 42;
    const least = fanout / 2;
    const Node = struct {
        count: u32,
        leaf: bool,
        /// A leaf's span starts, or a lower bound of each child's.
        keys: [fanout]u32,
        /// A leaf's span lengths, or each child's longest.
        sizes: [fanout]u32,
        children: [fanout]u32,

        fn longest(n: *const Node) u32 {
            var m: u32 = 0;
            for (n.sizes[0..n.count]) |size| m = @max(m, size);
            return m;
        }
        /// The last entry whose key is at most `key`, else the first.
        fn route(n: *const Node, key: u32) u32 {
            var k: u32 = 0;
            while (k + 1 < n.count and n.keys[k + 1] <= key) k += 1;
            return k;
        }
        fn insertAt(n: *Node, k: u32, key: u32, size: u32, child: u32) void {
            var i = n.count;
            while (i > k) : (i -= 1) {
                n.keys[i] = n.keys[i - 1];
                n.sizes[i] = n.sizes[i - 1];
                n.children[i] = n.children[i - 1];
            }
            n.keys[k] = key;
            n.sizes[k] = size;
            n.children[k] = child;
            n.count += 1;
        }
        fn removeAt(n: *Node, k: u32) void {
            for (k..n.count - 1) |i| {
                n.keys[i] = n.keys[i + 1];
                n.sizes[i] = n.sizes[i + 1];
                n.children[i] = n.children[i + 1];
            }
            n.count -= 1;
        }
        /// Moves entries `from..` of `n` to the end of `into`.
        fn moveTail(n: *Node, from: u32, into: *Node) void {
            for (from..n.count) |i| into.insertAt(into.count, n.keys[i], n.sizes[i], n.children[i]);
            n.count = from;
        }
    };
    comptime {
        std.debug.assert(@sizeOf(Node) == 512);
    }
    const Nodes = SlotPool(Node, Node, .{});

    fn node(s: *const Spans, i: u32) *Node {
        return s.nodes.get(@fromBackingInt(i));
    }
    fn make(s: *Spans, leaf: bool) u32 {
        const created = s.nodes.create() catch assert.never("run pool tree outgrew its reserved nodes");
        created.value.count = 0;
        created.value.leaf = leaf;
        return created.handle.raw();
    }
    /// Room for a tree of `spans` spans and one change to it. Every node but the root holds at
    /// least `least` entries, so the leaves number at most spans / 21 + 1 and the nodes above them
    /// a twentieth of that plus one a level; a change splits at most one node a level and adds a
    /// root, and a 32-bit tree is at most eight levels deep: spans / 20 + 20 covers them all.
    fn reserve(s: *Spans, spans: u32) Region.Error!void {
        const need = spans / 20 + 20;
        try s.nodes.reserve(need -| @as(u32, @intCast(s.nodes.len())));
    }
    fn clear(s: *Spans) void {
        s.nodes.recycleAll();
        s.root = none;
        s.height = 0;
        s.total = 0;
    }

    /// The span with the least start whose length is at least `n`.
    fn firstFit(s: *const Spans, n: u32) ?Span {
        if (s.root == none) return null;
        var at = s.root;
        descend: while (true) {
            const nd = s.node(at);
            for (0..nd.count) |k| if (nd.sizes[k] >= n) {
                if (nd.leaf) return .{ .start = nd.keys[k], .len = nd.sizes[k] };
                at = nd.children[k];
                continue :descend;
            };
            if (at == s.root) return null;
            assert.never("run pool tree's lengths disagree with its spans");
        }
    }
    /// The span with the greatest start below `key`.
    fn below(s: *const Spans, key: u32) ?Span {
        return if (s.root == none) null else s.belowIn(s.root, key);
    }
    fn belowIn(s: *const Spans, at: u32, key: u32) ?Span {
        const nd = s.node(at);
        var k = nd.count;
        while (k > 0) {
            k -= 1;
            if (nd.keys[k] >= key) continue;
            if (nd.leaf) return .{ .start = nd.keys[k], .len = nd.sizes[k] };
            if (s.belowIn(nd.children[k], key)) |found| return found;
        }
        return null;
    }
    /// The span with the least start at or above `key`.
    fn atOrAfter(s: *const Spans, key: u32) ?Span {
        return if (s.root == none) null else s.atOrAfterIn(s.root, key);
    }
    fn atOrAfterIn(s: *const Spans, at: u32, key: u32) ?Span {
        const nd = s.node(at);
        if (nd.leaf) {
            for (0..nd.count) |k| if (nd.keys[k] >= key) return .{ .start = nd.keys[k], .len = nd.sizes[k] };
            return null;
        }
        for (nd.route(key)..nd.count) |k| if (s.atOrAfterIn(nd.children[k], key)) |found| return found;
        return null;
    }

    fn insert(s: *Spans, span: Span) void {
        s.total += span.len;
        if (s.root == none) {
            s.root = s.make(true);
            s.node(s.root).insertAt(0, span.start, span.len, 0);
            return;
        }
        if (s.insertIn(s.root, span)) |split| {
            const old = s.root;
            const top = s.make(false);
            const nd = s.node(top);
            const left = s.node(old);
            nd.insertAt(0, left.keys[0], left.longest(), old);
            nd.insertAt(1, split.key, split.size, split.node);
            s.root = top;
            s.height += 1;
        }
    }
    const Split = struct { node: u32, key: u32, size: u32 };
    fn insertIn(s: *Spans, at: u32, span: Span) ?Split {
        const nd = s.node(at);
        var k: u32 = undefined;
        var child: u32 = 0;
        var size = span.len;
        var key = span.start;
        if (nd.leaf) {
            k = 0;
            while (k < nd.count and nd.keys[k] < span.start) k += 1;
        } else {
            const into = nd.route(span.start);
            if (span.start < nd.keys[into]) nd.keys[into] = span.start;
            const split = s.insertIn(nd.children[into], span);
            nd.sizes[into] = s.node(nd.children[into]).longest();
            const made = split orelse return null;
            k = into + 1;
            child = made.node;
            size = made.size;
            key = made.key;
        }
        if (nd.count < fanout) {
            nd.insertAt(k, key, size, child);
            return null;
        }
        const right_at = s.make(nd.leaf);
        const right = s.node(right_at);
        nd.moveTail(least, right);
        if (k <= least) nd.insertAt(k, key, size, child) else right.insertAt(k - least, key, size, child);
        return .{ .node = right_at, .key = right.keys[0], .size = right.longest() };
    }

    fn remove(s: *Spans, start: u32) void {
        s.total -= s.removeIn(s.root, start);
        const root = s.node(s.root);
        if (root.leaf and root.count == 0) {
            s.nodes.free(@fromBackingInt(s.root));
            s.root = none;
        } else if (!root.leaf and root.count == 1) {
            const only = root.children[0];
            s.nodes.free(@fromBackingInt(s.root));
            s.root = only;
            s.height -= 1;
        }
    }
    /// Removes the span at `start` below `at`; returns its length.
    fn removeIn(s: *Spans, at: u32, start: u32) u32 {
        const nd = s.node(at);
        if (nd.leaf) {
            for (0..nd.count) |k| if (nd.keys[k] == start) {
                const len = nd.sizes[k];
                nd.removeAt(@intCast(k));
                return len;
            };
            assert.never("run pool tree lost a free span");
        }
        const k = nd.route(start);
        const len = s.removeIn(nd.children[k], start);
        const child = s.node(nd.children[k]);
        if (child.count >= least or nd.count == 1) {
            nd.sizes[k] = child.longest();
            return len;
        }
        // Too few entries: take one from a sibling that can spare it, else join the sibling.
        const left_k = if (k > 0) k - 1 else k;
        const left = s.node(nd.children[left_k]);
        const right = s.node(nd.children[left_k + 1]);
        if (left.count + right.count <= fanout) {
            right.moveTail(0, left);
            s.nodes.free(@fromBackingInt(nd.children[left_k + 1]));
            nd.removeAt(left_k + 1);
        } else if (left.count > right.count) {
            const last = left.count - 1;
            right.insertAt(0, left.keys[last], left.sizes[last], left.children[last]);
            left.count = last;
            nd.keys[left_k + 1] = right.keys[0];
            nd.sizes[left_k + 1] = right.longest();
        } else {
            left.insertAt(left.count, right.keys[0], right.sizes[0], right.children[0]);
            right.removeAt(0);
            nd.keys[left_k + 1] = right.keys[0];
            nd.sizes[left_k + 1] = right.longest();
        }
        nd.sizes[left_k] = left.longest();
        return len;
    }

    /// Moves the span at `start` to `to` (never below it, never to or past the next span) with
    /// `len` items.
    fn set(s: *Spans, start: u32, to: u32, len: u32) void {
        s.total = s.total - s.setIn(s.root, start, to, len) + len;
    }
    fn setIn(s: *Spans, at: u32, start: u32, to: u32, len: u32) u32 {
        const nd = s.node(at);
        if (nd.leaf) {
            for (0..nd.count) |k| if (nd.keys[k] == start) {
                const old = nd.sizes[k];
                nd.keys[k] = to;
                nd.sizes[k] = len;
                return old;
            };
            assert.never("run pool tree lost a free span");
        }
        const k = nd.route(start);
        const old = s.setIn(nd.children[k], start, to, len);
        nd.sizes[k] = s.node(nd.children[k]).longest();
        return old;
    }
};
