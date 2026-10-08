const a = @import("aegis");
fn take(_: a.int.Checked(u64)) void {}
export fn bad() void {
    take(a.int.Saturating(u64).init(1));
}
