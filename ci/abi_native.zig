const abi = @import("abi.zig");
pub fn main() !void {
    try abi.nativeCheck();
}
