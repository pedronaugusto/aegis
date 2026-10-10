//! Reader-writer form of `Guarded`: many readers or one writer behind one atomic word.
const std = @import("std");

/// Couples data to a spin reader-writer lock. After publication the owner address must remain stable.
/// Infallible/noncancelable. Sections must be bounded, as `Guarded`'s: no blocking, yielding, recursion or
/// arbitrary callbacks, and no upgrade or downgrade. A waiting writer holds off new readers, so a stream of
/// readers cannot starve it; readers of a released writer's turn are admitted in no order. Read borrows do not
/// make mutable pointees thread-safe. All users must end before teardown.
pub fn SpinRwGuarded(comptime T: type) type {
    return struct {
        const Self = @This();
        /// Marks the owner as safe to share through a mutable pointer: all access is behind its lock.
        pub const interior_lock = true;
        const writing: u32 = 1 << 31;
        const waiting: u32 = 1 << 30;
        const readers: u32 = waiting - 1;
        /// The most readers at once; one more would reach the writer bits.
        pub const maximum_readers: u32 = readers;
        /// Private: the reader count, the waiting-writer bit and the writing bit.
        state: std.atomic.Value(u32) = .init(0),
        /// Private: use a live guard; never copy/move a published owner.
        data: T,

        pub fn init(value: T) Self {
            return .{ .data = value };
        }

        /// Shared access, waiting while a writer holds the lock or waits for it. Pair with `defer guard.deinit()`.
        pub fn read(owner: *Self) ReadGuard {
            while (true) {
                if (owner.tryReadOnce()) return .{ .owner = owner };
                while (owner.state.load(.monotonic) & (writing | waiting) != 0) std.atomic.spinLoopHint();
            }
        }

        /// Shared access if no writer holds or awaits the lock right now, otherwise null. Never waits.
        pub fn tryRead(owner: *Self) ?ReadGuard {
            return if (owner.tryReadOnce()) .{ .owner = owner } else null;
        }

        fn tryReadOnce(owner: *Self) bool {
            var current = owner.state.load(.monotonic);
            while (current & (writing | waiting) == 0) {
                std.debug.assert(current & readers != readers);
                current = owner.state.cmpxchgWeak(current, current + 1, .acquire, .monotonic) orelse return true;
            }
            return false;
        }

        /// Exclusive access, waiting for the readers and any writer ahead to end. Pair with `defer guard.deinit()`.
        pub fn write(owner: *Self) WriteGuard {
            while (true) {
                var current = owner.state.load(.monotonic);
                if (current & (writing | readers) == 0) {
                    current = owner.state.cmpxchgWeak(current, (current & ~waiting) | writing, .acquire, .monotonic) orelse return .{ .owner = owner };
                    continue;
                }
                // Hold off new readers while the present ones end.
                if (current & waiting == 0) _ = owner.state.fetchOr(waiting, .monotonic);
                std.atomic.spinLoopHint();
            }
        }

        /// Exclusive access if the lock is free right now, otherwise null. Never waits.
        pub fn tryWrite(owner: *Self) ?WriteGuard {
            var current = owner.state.load(.monotonic);
            while (current & (writing | readers) == 0) {
                current = owner.state.cmpxchgWeak(current, (current & ~waiting) | writing, .acquire, .monotonic) orelse return .{ .owner = owner };
            }
            return null;
        }

        /// Whether some task holds the lock, for reading or writing, at this instant. A snapshot for tests
        /// and diagnostics, never a substitute for acquiring.
        pub fn isHeld(owner: *const Self) bool {
            return owner.state.load(.acquire) & (writing | readers) != 0;
        }

        /// The data of an owner that no other task can reach: for the sole owner's teardown. Asserts the lock
        /// is free in Debug and ReleaseSafe.
        pub fn teardown(owner: *Self) *T {
            std.debug.assert(owner.state.load(.monotonic) & (writing | readers | waiting) == 0);
            return &owner.data;
        }

        pub const ReadGuard = struct {
            owner: *Self,

            /// Borrow until release. Several readers hold the data at once.
            pub fn value(guard: *const ReadGuard) *const T {
                return &guard.owner.data;
            }

            /// Release and consume this capability.
            pub fn deinit(guard: *ReadGuard) void {
                const before = guard.owner.state.fetchSub(1, .release);
                std.debug.assert(before & readers != 0);
            }
        };

        pub const WriteGuard = struct {
            owner: *Self,

            /// Borrow until release. No reader or writer holds the data meanwhile.
            pub fn value(guard: *const WriteGuard) *T {
                return &guard.owner.data;
            }

            /// Release with publication ordering and consume this capability.
            pub fn deinit(guard: *WriteGuard) void {
                const before = guard.owner.state.fetchAnd(~writing, .release);
                std.debug.assert(before & writing != 0);
            }
        };
    };
}

const Table = struct { a: u64 = 0, b: u64 = 0 };

fn writer(owner: *SpinRwGuarded(Table), rounds: usize) void {
    for (0..rounds) |_| {
        var held = owner.write();
        defer held.deinit();
        const table = held.value();
        table.a += 1;
        table.b += 1;
    }
}

fn reader(owner: *SpinRwGuarded(Table), rounds: usize, torn: *std.atomic.Value(usize)) void {
    for (0..rounds) |_| {
        var held = owner.read();
        defer held.deinit();
        if (held.value().a != held.value().b) _ = torn.fetchAdd(1, .monotonic);
    }
}

test "SpinRwGuarded readers share, a writer excludes them, and try forms never wait" {
    var owner = SpinRwGuarded(u32).init(5);
    var first = owner.read();
    var second = owner.tryRead().?;
    try std.testing.expectEqual(@as(u32, 5), first.value().*);
    try std.testing.expect(owner.isHeld());
    try std.testing.expect(owner.tryWrite() == null);
    first.deinit();
    try std.testing.expect(owner.tryWrite() == null);
    second.deinit();
    try std.testing.expect(!owner.isHeld());
    var held = owner.tryWrite().?;
    held.value().* = 6;
    try std.testing.expect(owner.tryRead() == null);
    try std.testing.expect(owner.tryWrite() == null);
    held.deinit();
    var again = owner.read();
    defer again.deinit();
    try std.testing.expectEqual(@as(u32, 6), again.value().*);
}

test "SpinRwGuarded teardown hands a free owner its data" {
    var owner = SpinRwGuarded([2]u8).init(.{ 1, 2 });
    try std.testing.expectEqual(@as(u8, 2), owner.teardown()[1]);
    try std.testing.expect(!owner.isHeld());
}

test "SpinRwGuarded writers exclude each other and readers never see a torn pair" {
    var owner = SpinRwGuarded(Table).init(.{});
    var torn: std.atomic.Value(usize) = .init(0);
    var group: std.Io.Group = .init;
    defer group.cancel(std.testing.io);
    for (0..3) |_| try group.concurrent(std.testing.io, writer, .{ &owner, 2000 });
    for (0..4) |_| try group.concurrent(std.testing.io, reader, .{ &owner, 4000, &torn });
    try group.await(std.testing.io);
    try std.testing.expectEqual(@as(usize, 0), torn.load(.monotonic));
    var held = owner.read();
    defer held.deinit();
    try std.testing.expectEqual(@as(u64, 6000), held.value().a);
    try std.testing.expectEqual(@as(u64, 6000), held.value().b);
}
