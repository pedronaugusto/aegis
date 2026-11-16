//! A validated machine's tables read at run time: glint's P007 seam for it (glint.json), and
//! nothing else lives here. `Machine` builds its tables at comptime from the edges it analyzed, so
//! a row or column is the position of a valid enum value, and a cell is a state's position or the
//! row count, none. Debug keeps the reads' bounds and range checks; the other builds read the
//! table as a hand-written one does (the parity contracts hold them to it, ReleaseSafe included).
const builtin = @import("builtin");

/// The state at `cells[row][column]`, or null where the cell is none: `row` and `column` are
/// positions of valid enum values, and `members` holds `S`'s members in position order.
pub inline fn state(comptime S: type, comptime dense: bool, comptime cells: anytype, comptime members: [cells.len]S, row: usize, column: usize) ?S {
    @setRuntimeSafety(builtin.optimize == .debug); // safe: positions of valid enum values index the comptime table, whose cells are states' positions or none
    const cell = cells[row][column];
    if (cell == cells.len) return null;
    return if (dense) @fromBackingInt(@as(@typeInfo(S).@"enum".tag_type, @intCast(cell))) else members[cell];
}

/// `flags[at]`: `at` is the position of a valid enum value among the table's members.
pub inline fn flag(comptime flags: anytype, at: usize) bool {
    @setRuntimeSafety(builtin.optimize == .debug); // safe: the position of a valid enum value indexes the comptime table
    return flags[at];
}
