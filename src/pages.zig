//! The system's virtual memory, as whole pages of one reservation: glint's P007 seam for it
//! (glint.json), and nothing else lives here. Each call takes the reservation and the pages of it
//! meant, and touches only those. A reservation's length is asserted in every build; that the
//! pages a later call is handed are whole and inside it is asserted in Debug, and the safe builds keep the language's own checks of what a call computes (the length past the
//! committed end, and the page alignment of `@alignCast`), so in ReleaseSafe and ReleaseFast a
//! region's growth is the code a hand-written owner compiles to (the parity contracts hold it to
//! that). `Region` is its one caller.
const builtin = @import("builtin");
const std = @import("std");
const assert = @import("assert.zig");
const posix = std.posix;
const windows = std.os.windows;

/// Whether a call asserts what it is handed.
const checked = builtin.optimize == .debug;

/// Whole pages of a reservation.
pub const Pages = []align(std.heap.page_size_min) u8;

/// Reserves `length` bytes of address space, a whole number of pages, inaccessible and charged
/// to nobody until committed.
pub fn reserve(length: usize) error{OutOfMemory}!Pages {
    assert.invariant(length != 0 and length % std.heap.pageSize() == 0, "virtual memory is whole pages");
    if (builtin.os.tag == .windows) {
        var base: ?*anyopaque = null;
        var size: windows.SIZE_T = length;
        const status = windows.ntdll.NtAllocateVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base), 0, &size, .{ .RESERVE = true }, .{ .NOACCESS = true }); // safe: NtAllocateVirtualMemory writes the base through a PVOID pointer
        if (status != .SUCCESS) return error.OutOfMemory;
        const start: [*]align(std.heap.page_size_min) u8 = @ptrCast(@alignCast(base)); // safe: the system's reservation starts on a page
        return start[0..length];
    }
    return posix.mmap(null, length, .{}, reservation, -1, 0) catch return error.OutOfMemory;
}

/// Gives a reservation back: `committed` is its committed start, `reservation_len` its length.
pub fn release(committed: []u8, reservation_len: usize) void {
    const memory = paged(committed.ptr, reservation_len);
    if (builtin.os.tag == .windows) {
        var base: ?*anyopaque = memory.ptr;
        var size: windows.SIZE_T = 0;
        const status = windows.ntdll.NtFreeVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base), &size, .{ .RELEASE = true }); // safe: NtFreeVirtualMemory reads the base through a PVOID pointer
        assert.invariant(status == .SUCCESS, "the system releases a reservation it made");
        return;
    }
    posix.munmap(memory);
}

/// Commits a reservation's pages past `committed`, its committed start, up to `len`, at most
/// `reservation_len`, and returns the reservation's first `len` bytes, all committed. On a refusal
/// nothing changes.
pub fn commit(committed: []u8, reservation_len: usize, len: usize) error{OutOfMemory}![]u8 {
    if (checked) assert.invariant(committed.len <= len and len <= reservation_len, "a commit grows inside its reservation");
    const fresh = paged(committed.ptr + committed.len, len - committed.len);
    if (builtin.os.tag == .windows) {
        var base: ?*anyopaque = fresh.ptr;
        var size: windows.SIZE_T = fresh.len;
        const status = windows.ntdll.NtAllocateVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base), 0, &size, .{ .COMMIT = true }, .{ .READWRITE = true }); // safe: NtAllocateVirtualMemory reads the base through a PVOID pointer
        if (status != .SUCCESS) return error.OutOfMemory;
    } else {
        std.process.protectMemory(fresh, .{ .read = true, .write = true }) catch return error.OutOfMemory;
    }
    return committed.ptr[0..len];
}

/// Gives the committed pages of `committed` from `keep` on back: a fresh inaccessible mapping
/// over them on POSIX, which drops their contents and their charge, and a decommit on Windows.
/// False when the system refused, with the pages as they were.
pub fn decommit(committed: []u8, keep: usize) bool {
    const memory = paged(committed.ptr + keep, committed.len - keep);
    if (builtin.os.tag == .windows) {
        var base: ?*anyopaque = memory.ptr;
        var size: windows.SIZE_T = memory.len;
        return windows.ntdll.NtFreeVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base), &size, .{ .DECOMMIT = true }) == .SUCCESS; // safe: NtFreeVirtualMemory reads the base through a PVOID pointer
    }
    var flags = reservation;
    flags.FIXED = true;
    _ = posix.mmap(memory.ptr, memory.len, .{}, flags, -1, 0) catch return false;
    return true;
}

/// Private, anonymous, and charged to nobody until committed, where the system has the flag.
const reservation: posix.MAP = flags: {
    var flags: posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
    if (@hasField(posix.MAP, "NORESERVE")) flags.NORESERVE = true;
    break :flags flags;
};

/// The `len` bytes at `start`, whole pages: `start` is on a page and `len` a whole number of them.
fn paged(start: [*]u8, len: usize) Pages {
    if (checked) {
        const page = std.heap.pageSize();
        assert.invariant(len != 0 and len % page == 0 and @intFromPtr(start) % page == 0, "virtual memory is whole pages");
    }
    const first: [*]align(std.heap.page_size_min) u8 = @alignCast(start); // safe: on a page, asserted in Debug and checked by @alignCast in the safe builds
    return first[0..len];
}
