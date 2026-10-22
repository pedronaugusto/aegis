//! A file descriptor that must be closed and a result that must be read: owners with one
//! static cleanup, handed on explicitly, checked for discharge in Debug.
const aegis = @import("aegis");

const own = aegis.own;
var closed: u32 = 0;

fn close(fd: *i32) void {
    fd.* = -1;
    closed += 1;
}

const Descriptor = own.Owned(i32, close);

const Report = struct { written: usize };

fn flush(written: usize) own.MustUse(Report, "a flush's report says how much reached the disk") {
    return .init(.{ .written = written });
}

pub fn main() !void {
    var file = Descriptor.init(3);
    aegis.assert.post(file.borrow().* == 3, "borrowed in place");

    // Ownership moves into disjoint storage; the source owes nothing after.
    var kept: Descriptor = undefined;
    file.moveInto(&kept);
    kept.deinit();
    aegis.assert.post(closed == 1, "closed once, by the owner that had it");

    // A result that must be looked at: taken, or acknowledged with a stated reason.
    var report = flush(512);
    var read: Report = undefined;
    report.take(&read);
    report.deinit();
    aegis.assert.post(read.written == 512, "the report was read");
    var ignored = flush(0);
    ignored.acknowledge("an empty flush writes nothing to report");
    ignored.deinit();
    // Dropping `flush(..)` without either stops a Debug build at its `deinit`.
}
