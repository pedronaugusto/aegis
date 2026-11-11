//! Stream ends that state why they failed. std's `*Io.Reader` and `*Io.Writer` return only `ReadFailed` and
//! `WriteFailed`; the cause (a cancel among them) stays in the concrete end's own `err`, which code handed the
//! bare interface cannot reach. An end here carries the interface and the way to that cause, and is made only
//! by stating where the cause lives.
const std = @import("std");
const Io = std.Io;

/// How an end reads its cause: from its context, the error of its last failure, or null where none is recorded.
pub const FailureFn = *const fn (context: *const anyopaque) ?anyerror;

/// A reader with its cause: hand `reader()` to code that reads, and ask `failure()` or `settle` when a read
/// returned `ReadFailed`. Made only by a constructor that says where the cause is: `fromFile`, `fromStream`,
/// `causeless` for an end that records none, or `init` for another package's end (a TLS session, a tunnel, a
/// test double) with its own accessor. The end borrows what it was made from, which must outlive it.
pub const ReadEnd = struct {
    /// Private: the std interface reads go through.
    interface: *Io.Reader,
    /// Private: what `failure_fn` reads the cause from.
    context: *const anyopaque,
    /// Private: the cause of the last failed read.
    failure_fn: FailureFn,

    /// Another package's end: its interface, and how to read why its last read failed.
    pub fn init(interface: *Io.Reader, context: *const anyopaque, failure_fn: FailureFn) ReadEnd {
        return .{ .interface = interface, .context = context, .failure_fn = failure_fn };
    }

    /// A file reader's end: its cause is the reader's own `err`.
    pub fn fromFile(file: *Io.File.Reader) ReadEnd {
        return .init(&file.interface, file, fileReadCause);
    }

    /// A network stream reader's end: its cause is the reader's own `err`.
    pub fn fromStream(stream: *Io.net.Stream.Reader) ReadEnd {
        return .init(&stream.interface, stream, streamReadCause);
    }

    /// An end that records no cause, stated as such: a fixed buffer, which fails only by ending, or a test double.
    pub fn causeless(interface: *Io.Reader) ReadEnd {
        return .init(interface, interface, noCause);
    }

    /// The std interface, for code that reads.
    pub fn reader(end: ReadEnd) *Io.Reader {
        return end.interface;
    }

    /// Why the last read failed, or null where the end records nothing.
    pub fn failure(end: ReadEnd) ?anyerror {
        return end.failure_fn(end.context);
    }

    /// `ReadFailed` as what it was: `Canceled` where the end's cause is a cancel, so a cancel is never reported
    /// as a failed read; `ReadFailed` otherwise.
    pub fn settle(end: ReadEnd, failed: error{ReadFailed}) error{ ReadFailed, Canceled } {
        if (end.failure()) |cause| if (cause == error.Canceled) return error.Canceled;
        return failed;
    }
};

/// A writer with its cause, as `ReadEnd` is a reader's: `writer()` for code that writes, `failure()` and `settle`
/// for a `WriteFailed`.
pub const WriteEnd = struct {
    /// Private: the std interface writes go through.
    interface: *Io.Writer,
    /// Private: what `failure_fn` reads the cause from.
    context: *const anyopaque,
    /// Private: the cause of the last failed write.
    failure_fn: FailureFn,

    /// Another package's end: its interface, and how to read why its last write failed.
    pub fn init(interface: *Io.Writer, context: *const anyopaque, failure_fn: FailureFn) WriteEnd {
        return .{ .interface = interface, .context = context, .failure_fn = failure_fn };
    }

    /// A file writer's end: its cause is the writer's own `err`, else its `sendFile` error.
    pub fn fromFile(file: *Io.File.Writer) WriteEnd {
        return .init(&file.interface, file, fileWriteCause);
    }

    /// A network stream writer's end: its cause is the writer's own `err`, else its `sendFile` error.
    pub fn fromStream(stream: *Io.net.Stream.Writer) WriteEnd {
        return .init(&stream.interface, stream, streamWriteCause);
    }

    /// An end that records no cause, stated as such: a fixed buffer or a test double.
    pub fn causeless(interface: *Io.Writer) WriteEnd {
        return .init(interface, interface, noCause);
    }

    /// The std interface, for code that writes.
    pub fn writer(end: WriteEnd) *Io.Writer {
        return end.interface;
    }

    /// Why the last write failed, or null where the end records nothing.
    pub fn failure(end: WriteEnd) ?anyerror {
        return end.failure_fn(end.context);
    }

    /// `WriteFailed` as what it was: `Canceled` where the end's cause is a cancel; `WriteFailed` otherwise.
    pub fn settle(end: WriteEnd, failed: error{WriteFailed}) error{ WriteFailed, Canceled } {
        if (end.failure()) |cause| if (cause == error.Canceled) return error.Canceled;
        return failed;
    }
};

fn noCause(_: *const anyopaque) ?anyerror {
    return null;
}
fn fileReadCause(context: *const anyopaque) ?anyerror {
    const file: *const Io.File.Reader = @ptrCast(@alignCast(context)); // safe: fromFile passes a File.Reader
    return file.err;
}
fn streamReadCause(context: *const anyopaque) ?anyerror {
    const stream: *const Io.net.Stream.Reader = @ptrCast(@alignCast(context)); // safe: fromStream passes a Stream.Reader
    return stream.err;
}
fn fileWriteCause(context: *const anyopaque) ?anyerror {
    const file: *const Io.File.Writer = @ptrCast(@alignCast(context)); // safe: fromFile passes a File.Writer
    return if (file.err) |err| err else if (file.write_file_err) |err| err else null;
}
fn streamWriteCause(context: *const anyopaque) ?anyerror {
    const stream: *const Io.net.Stream.Writer = @ptrCast(@alignCast(context)); // safe: fromStream passes a Stream.Writer
    return if (stream.err) |err| err else if (stream.write_file_err) |err| err else null;
}

const t = std.testing;

test "a file reader's end states a cancel as Canceled, any other cause as ReadFailed with the cause kept" {
    var buffer: [8]u8 = undefined;
    var file: Io.File.Reader = .initStreaming(.stdin(), t.io, &buffer);
    const end: ReadEnd = .fromFile(&file);
    try t.expect(end.reader() == &file.interface);
    try t.expect(end.failure() == null);
    file.err = error.Canceled;
    try t.expectEqual(error.Canceled, end.settle(error.ReadFailed));
    file.err = error.InputOutput;
    try t.expect(end.failure().? == error.InputOutput);
    try t.expectEqual(error.ReadFailed, end.settle(error.ReadFailed));
}

test "a file writer's end reads its own err, then its sendFile error" {
    var buffer: [8]u8 = undefined;
    var file: Io.File.Writer = .initStreaming(.stdout(), t.io, &buffer);
    const end: WriteEnd = .fromFile(&file);
    try t.expect(end.writer() == &file.interface);
    try t.expect(end.failure() == null);
    file.write_file_err = error.Unimplemented;
    try t.expect(end.failure().? == error.Unimplemented);
    file.err = error.Canceled;
    try t.expectEqual(error.Canceled, end.settle(error.WriteFailed));
}

test "a causeless end says so, and another package's end answers through its own accessor" {
    var fixed: Io.Reader = .fixed("abc");
    const plain: ReadEnd = .causeless(&fixed);
    try t.expect(plain.failure() == null);
    try t.expectEqual(error.ReadFailed, plain.settle(error.ReadFailed));
    // A session layered over another end keeps its own cause.
    const Session = struct {
        reader: Io.Reader,
        cause: ?anyerror = null,
        fn failureOf(context: *const anyopaque) ?anyerror {
            const self: *const @This() = @ptrCast(@alignCast(context)); // safe: the test passes its Session
            return self.cause;
        }
    };
    var session: Session = .{ .reader = .fixed("") };
    const layered: ReadEnd = .init(&session.reader, &session, Session.failureOf);
    session.cause = error.Canceled;
    try t.expectEqual(error.Canceled, layered.settle(error.ReadFailed));
    var sink: [4]u8 = undefined;
    var out: Io.Writer = .fixed(&sink);
    const written: WriteEnd = .causeless(&out);
    try t.expectEqual(error.WriteFailed, written.settle(error.WriteFailed));
}
