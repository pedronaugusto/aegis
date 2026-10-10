//! The record of a transition: declared in a specification, or taken at run time.

/// `from` on `on` leads to `to`.
pub fn Edge(comptime S: type, comptime E: type) type {
    return struct { from: S, on: E, to: S };
}
