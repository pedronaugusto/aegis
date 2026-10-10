const aegis = @import("aegis");

// --- README:state ---
const Session = aegis.state.Machine(enum { pending, authenticated, closed }, enum { verify, close }, .{
    .initial = .pending,
    .terminal = &.{.closed},
    .edges = &.{
        .{ .from = .pending, .on = .verify, .to = .authenticated },
        .{ .from = .authenticated, .on = .close, .to = .closed },
    },
});
const Credentials = struct { token: u64 };
const Receipt = struct { account: u32 };
const Pending = Session.At(.pending, Credentials);
const Authenticated = Session.At(.authenticated, Receipt);

/// The one place a receipt is made: it checks the credentials and fails before anything moves.
fn verify(expected: u64, credentials: *Credentials, receipt: *Receipt) error{BadToken}!void {
    if (credentials.token != expected) return error.BadToken;
    receipt.* = .{ .account = 7 };
}

/// Takes an authenticated stage, so a pending one does not compile here.
fn send(session: *Authenticated, message: []const u8) usize {
    return message.len + session.get().account;
}

pub fn main() !void {
    var pending = Pending.init(.{ .token = 42 });
    var authenticated: Authenticated = undefined;
    if (pending.transitionWith(.verify, &authenticated, @as(u64, 41), verify)) |_| unreachable else |err| aegis.assert.invariant(err == error.BadToken, "a wrong token is refused");
    try pending.transitionWith(.verify, &authenticated, @as(u64, 42), verify); // consumes `pending`
    aegis.assert.post(send(&authenticated, "hello") == 12, "a message is sent on the authenticated stage");

    // Events from a peer arrive at run time: an undeclared one is an error, never a state change.
    var link = Session.Runtime(u32).init(0);
    _ = try link.step(.verify);
    if (link.step(.verify)) |_| unreachable else |err| aegis.assert.invariant(err == error.IllegalEvent, "an undeclared event is refused");
    aegis.assert.post(link.current() == .authenticated, "the refused event changed nothing");
}
// --- README:state ---
