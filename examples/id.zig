//! Record sequence numbers that are their own type: issued without wrapping, moved only by a
//! count of records, never mixed with another domain's ids.
const std = @import("std");
const aegis = @import("aegis");

const Record = struct {};
const Connection = struct {};
const Sequence = aegis.id.Id(Record, u64);
const ConnectionId = aegis.id.NonZero(Connection, u32);

pub fn main() !void {
    var issuer = aegis.id.Counter(Record, u64).init(0);
    aegis.assert.invariant(issuer.last() == null, "nothing issued yet");
    const first = try issuer.next();
    const second = try issuer.next();
    aegis.assert.invariant(second.compare(first) == .gt and issuer.last().?.eql(second), "issued in order, the last one readable");

    // A sequence moves by a count of records, and only by that.
    const later = try first.advance(.fromRaw(10));
    aegis.assert.invariant((try first.distanceTo(later)).eql(.fromRaw(10)), "distance is a count of records");
    if (later.distanceTo(first)) |_| unreachable else |err| aegis.assert.invariant(err == error.Backwards, "a distance never runs backwards");

    // At the top, the next id is an error, not zero.
    if (Sequence.fromRaw(std.math.maxInt(u64)).successor()) |_| unreachable else |err| aegis.assert.invariant(err == error.IdExhausted, "ids never wrap");

    // A NonZero id refuses zero where it enters, from a raw integer or from the wire.
    if (ConnectionId.fromRaw(0)) |_| unreachable else |err| aegis.assert.invariant(err == error.InvalidId, "zero is not a connection");
    const peer = try ConnectionId.fromRaw(9);
    const wire = peer.toBytes(.big);
    aegis.assert.invariant((try ConnectionId.fromBytes(wire, .big)).eql(peer), "encoded in a stated byte order");
    // `peer.eql(first)` does not compile: a connection is not a record.
}
