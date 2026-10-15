//! The builds `zig build check-choices` inspects: a target and a CPU model, each compiled
//! with Zig 0.17.0's LLVM backend in every optimize mode and side-channel mitigation level.
//! `Choice.audited` is true for a build that is one of them. Pure data: no imports.

pub const Profile = struct {
    /// The target triple as `-target` takes it.
    target: []const u8,
    /// The CPU model as `-mcpu` takes it; "baseline" is the target's baseline.
    cpu: []const u8,
};

pub const all = [_]Profile{
    .{ .target = "x86_64-linux-gnu", .cpu = "baseline" },
    .{ .target = "x86_64-linux-gnu", .cpu = "x86_64_v2" },
    .{ .target = "x86_64-linux-gnu", .cpu = "x86_64_v3" },
    .{ .target = "x86_64-linux-gnu", .cpu = "x86_64_v4" },
    .{ .target = "x86_64-linux-musl", .cpu = "baseline" },
    .{ .target = "aarch64-linux-gnu", .cpu = "baseline" },
    .{ .target = "aarch64-linux-gnu", .cpu = "neoverse_n1" },
    .{ .target = "aarch64-linux-gnu", .cpu = "neoverse_v2" },
    .{ .target = "x86_64-windows-gnu", .cpu = "baseline" },
    .{ .target = "aarch64-windows-gnu", .cpu = "baseline" },
    .{ .target = "x86_64-macos", .cpu = "baseline" },
    .{ .target = "aarch64-macos", .cpu = "baseline" },
    .{ .target = "aarch64-macos", .cpu = "apple_m2" },
    .{ .target = "aarch64-macos", .cpu = "apple_m3" },
    .{ .target = "aarch64-macos", .cpu = "apple_m4" },
    .{ .target = "x86_64-freebsd", .cpu = "baseline" },
    .{ .target = "x86_64-openbsd", .cpu = "baseline" },
    .{ .target = "x86_64-netbsd", .cpu = "baseline" },
    .{ .target = "x86_64-dragonfly", .cpu = "baseline" },
    .{ .target = "wasm32-freestanding", .cpu = "baseline" },
};
