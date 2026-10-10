//! Comptime typestate: a validated topology, statically staged payloads and a checked runtime table.
/// A transition: `from` on `on` leads to `to`. Specifications list them and `Runtime` reports the one taken.
pub const Edge = @import("state/edge.zig").Edge;
/// What a machine is built from: its initial and terminal states and its edges.
pub const Spec = @import("state/machine.zig").Spec;
/// A topology over a state enum and an event enum, validated when it is analyzed.
pub const Machine = @import("state/machine.zig").Machine;
