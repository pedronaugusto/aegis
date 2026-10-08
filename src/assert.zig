//! Executable programmer contracts. Peer failures belong in error returns.
const builtin = @import("builtin");

/// Fail-stop in every build; does not unwind cleanup or assume unreachable.
// ziglint-ignore: Z023 condition then static message is the specified scalar contract
pub fn invariant(condition: bool, comptime message: []const u8) void {
    if (!condition) @panic(message);
}
/// Always-on caller precondition, evaluated once.
// ziglint-ignore: Z023 condition then static message is the specified scalar contract
pub fn pre(condition: bool, comptime message: []const u8) void {
    invariant(condition, message);
}
/// Always-on result postcondition, evaluated once.
// ziglint-ignore: Z023 condition then static message is the specified scalar contract
pub fn post(condition: bool, comptime message: []const u8) void {
    invariant(condition, message);
}
/// Optional Debug diagnostic; argument evaluation still belongs to the caller.
// ziglint-ignore: Z023 condition then static message is the specified scalar contract
pub fn debug(condition: bool, comptime message: []const u8) void {
    if (builtin.mode == .debug) invariant(condition, message);
}
/// Optional predicate call itself disappears in both release modes.
pub fn debugCheck(comptime predicate: anytype, context: anytype) void {
    if (builtin.mode == .debug) invariant(predicate(context), "aegis debug predicate");
}
/// Deliberately possible true or false; use only side-effect-free expressions.
pub fn maybe(condition: bool) void {
    _ = condition;
}
/// Caller-owned test coverage; never a global counter or likelihood hint.
pub const Coverage = struct { yes: usize = 0, no: usize = 0 };
/// Test-only instrumentation; counters deliberately saturate rather than fail.
pub fn maybeCount(condition: bool, coverage: *Coverage) void {
    if (builtin.is_test) {
        if (condition) coverage.yes +|= 1 else coverage.no +|= 1;
    }
}
