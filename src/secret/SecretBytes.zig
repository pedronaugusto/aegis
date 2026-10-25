//! One explicit owner of a full allocator allocation, including non-live slack. It holds no
//! allocator: the one that allocated it is passed to every call that allocates or frees (`init`,
//! `reserve`, `appendSlice`, `Writer.init`, `deinit`), as std's unmanaged containers take theirs.
const std = @import("std");
const SecretBytes = @This();

// Private by contract: never copy a live descriptor or truncate its allocation.
allocation: []u8,
used_len: usize,

/// No allocation: nothing to erase, and `deinit` frees nothing. Grows through `reserve` and
/// `appendSlice` like any other owner.
pub const empty: SecretBytes = .{ .allocation = &.{}, .used_len = 0 };

pub const InitError = std.mem.Allocator.Error;
pub const AdoptError = error{InvalidLength};
pub const ResizeError = error{CapacityExceeded};
pub const ReplaceError = error{ CapacityExceeded, Overlap };
pub const ReserveError = std.mem.Allocator.Error;
pub const AppendError = error{ OutOfMemory, Overlap };

/// Allocates and zeros full capacity; the live prefix starts empty.
/// Pair success immediately with defer/errdefer. No automatic cleanup on abort.
pub fn init(gpa: std.mem.Allocator, full_capacity: usize) InitError!SecretBytes {
    const allocation = try gpa.alloc(u8, full_capacity);
    @memset(allocation, 0);
    return .{ .allocation = allocation, .used_len = 0 };
}

/// Takes exclusive ownership of the full allocator-owned slice on success only.
/// Requires a byte allocation releasable with u8 alignment by the allocator later
/// passed to `reserve`, `appendSlice` and `deinit`.
/// The live prefix must be initialized; slack may be undefined. A slice cannot
/// prove allocator provenance, full extent or exclusivity: those are obligations
/// of the caller. Borrowed memory must never be adopted. Failure changes nothing.
pub fn adopt(allocation: []u8, live_len: usize) AdoptError!SecretBytes {
    if (live_len > allocation.len) return error.InvalidLength;
    return .{ .allocation = allocation, .used_len = live_len };
}

/// Number of live bytes.
pub fn len(self: *const SecretBytes) usize {
    return self.used_len;
}

/// Full extent that will be erased before free, including unused slack.
pub fn capacity(self: *const SecretBytes) usize {
    return self.allocation.len;
}

/// Borrows only the initialized live prefix. Ends at successful reserve, move
/// or cleanup; resize/replace can change its content. No concurrent mutation.
pub fn expose(self: *const SecretBytes) []const u8 {
    return self.allocation[0..self.used_len];
}

/// Mutable live-prefix borrow; the caller must erase displaced material.
pub fn exposeMut(self: *SecretBytes) []u8 {
    return self.allocation[0..self.used_len];
}

/// Shrink erases removed live bytes immediately; grow zeros newly live bytes.
/// Never allocates. Failure preserves ownership, content and existing borrows.
pub fn resizeWithinCapacity(self: *SecretBytes, new_len: usize) ResizeError!void {
    if (new_len > self.allocation.len) return error.CapacityExceeded;
    if (new_len < self.used_len) {
        std.crypto.secureZero(u8, self.allocation[new_len..self.used_len]);
    } else {
        @memset(self.allocation[self.used_len..new_len], 0);
    }
    self.used_len = new_len;
}

/// Disjoint input only: rejects overlap with ANY part of the backing allocation,
/// including slack, before mutation in every mode. No implicit capacity growth.
/// Empty input has no occupied bytes. Borrowed input remains caller-owned.
pub fn replace(self: *SecretBytes, bytes: []const u8) ReplaceError!void {
    if (bytes.len > self.allocation.len) return error.CapacityExceeded;
    if (self.overlaps(bytes)) return error.Overlap;
    std.crypto.secureZero(u8, self.allocation[0..self.used_len]);
    @memcpy(self.allocation[0..bytes.len], bytes);
    self.used_len = bytes.len;
}

/// Disjoint input only, as `replace`: appends `bytes` after the live prefix,
/// growing as `reserve` does (at least doubling), so no copy of the old
/// storage is left unerased. Failure changes nothing; growth ends borrows.
pub fn appendSlice(self: *SecretBytes, gpa: std.mem.Allocator, bytes: []const u8) AppendError!void {
    if (self.overlaps(bytes)) return error.Overlap;
    const new_len = std.math.add(usize, self.used_len, bytes.len) catch return error.OutOfMemory;
    if (new_len > self.allocation.len) try self.reserve(gpa, @max(new_len, self.allocation.len *| 2));
    @memcpy(self.allocation[self.used_len..new_len], bytes);
    self.used_len = new_len;
}

/// Whether `bytes` shares any address with the backing allocation, slack
/// included. Empty input has no occupied bytes.
fn overlaps(self: *const SecretBytes, bytes: []const u8) bool {
    if (bytes.len != 0 and self.allocation.len != 0) {
        const x = @intFromPtr(self.allocation.ptr); // safe: numerical address comparison only, no dereference
        const y = @intFromPtr(bytes.ptr); // safe: valid input slice address, compared without dereferencing
        // Subtract from the greater address: no end-pointer overflow.
        if (if (x <= y) y - x < self.allocation.len else x - y < bytes.len) return true;
    }
    return false;
}

/// A `std.Io.Writer` into the owner, after its live prefix. Its buffer is the
/// owner's allocation, so written bytes are never held anywhere else; growth
/// goes through `reserve`, which erases the storage it leaves. `flush`
/// publishes what was written as the owner's live prefix. While a writer is
/// open, the owner is used through it alone; `WriteFailed` is `err`'s
/// allocation failure.
pub const Writer = struct {
    owner: *SecretBytes,
    /// The owner's allocator, which grows it.
    gpa: std.mem.Allocator,
    interface: std.Io.Writer,
    err: ?ReserveError = null,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = flush, .rebase = rebase };

    pub fn init(owner: *SecretBytes, gpa: std.mem.Allocator) Writer {
        return .{ .owner = owner, .gpa = gpa, .interface = .{ .buffer = owner.allocation, .end = owner.used_len, .vtable = &vtable } };
    }

    fn of(w: *std.Io.Writer) *Writer {
        return @alignCast(@fieldParentPtr("interface", w)); // safe: the vtable is installed only on a Writer's interface
    }

    /// Room for `extra` bytes after what is written, through `reserve`.
    fn grow(self: *Writer, extra: usize) std.Io.Writer.Error!void {
        const owner = self.owner;
        owner.used_len = self.interface.end;
        const needed = std.math.add(usize, owner.used_len, extra) catch {
            self.err = error.OutOfMemory;
            return error.WriteFailed;
        };
        owner.reserve(self.gpa, @max(needed, owner.allocation.len *| 2)) catch |err| {
            self.err = err;
            return error.WriteFailed;
        };
        self.interface.buffer = owner.allocation;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self = of(w);
        const count = std.Io.Writer.countSplat(data, splat);
        if (w.buffer.len - w.end < count) try self.grow(count);
        for (data[0 .. data.len - 1]) |bytes| {
            @memcpy(w.buffer[w.end..][0..bytes.len], bytes);
            w.end += bytes.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            @memcpy(w.buffer[w.end..][0..pattern.len], pattern);
            w.end += pattern.len;
        }
        return count;
    }

    fn rebase(w: *std.Io.Writer, preserve: usize, minimum_len: usize) std.Io.Writer.Error!void {
        // Nothing written is ever let go, so all of it is preserved.
        _ = preserve;
        if (w.buffer.len - w.end < minimum_len) try of(w).grow(minimum_len);
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        of(w).owner.used_len = w.end;
    }
};

/// Explicit growth: allocate, zero, copy live prefix, erase ENTIRE old capacity,
/// free, then publish new storage. Never resize/remap or transfer a bare slice.
/// OOM preserves the old owner and all its borrows. Success ends old borrows.
/// A request at or below capacity is a no-op and preserves borrows.
pub fn reserve(self: *SecretBytes, gpa: std.mem.Allocator, new_capacity: usize) ReserveError!void {
    if (new_capacity <= self.allocation.len) return;
    const replacement = try gpa.alloc(u8, new_capacity);
    @memset(replacement, 0);
    @memcpy(replacement[0..self.used_len], self.expose());
    eraseAndFree(gpa, self.allocation);
    self.allocation = replacement;
}

/// Transfers into uninitialized disjoint descriptor storage, consuming self.
/// Allocation and live bytes move without allocation or copying their content;
/// all source borrows end. Destination must not already own resources and must
/// sit outside this owner's allocation (as must the source descriptor).
pub fn moveInto(self: *SecretBytes, destination: *SecretBytes) void {
    @setRuntimeSafety(true);
    @memcpy(std.mem.asBytes(destination), std.mem.asBytes(self));
    std.crypto.secureZero(u8, std.mem.asBytes(self));
}

/// Erases full capacity BEFORE free in every mode, then invalidates this owner.
/// Consumes self: no typed reads, reuse or second cleanup of the erased owner.
/// No promise of erasing prior compiler copies, registers, paging or core dumps.
pub fn deinit(self: *SecretBytes, gpa: std.mem.Allocator) void {
    eraseAndFree(gpa, self.allocation);
    self.* = undefined;
}

/// Fails before any output. Reflection/field access/exposure can bypass this.
pub fn format(_: *const SecretBytes, _: *std.Io.Writer) error{SecretNotFormattable}!void {
    return error.SecretNotFormattable;
}

fn eraseAndFree(gpa: std.mem.Allocator, allocation: []u8) void {
    std.crypto.secureZero(u8, allocation);
    // Allocator.free poisons memory in Debug before the hook. Use the byte
    // allocation's exact extent/alignment directly so the hook sees zero bytes.
    if (allocation.len != 0) gpa.rawFree(allocation, .fromByteUnits(@alignOf(u8)), @returnAddress());
}
