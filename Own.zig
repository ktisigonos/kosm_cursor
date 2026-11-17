//! A cursor theme of the user's own SVGs, one per cursor (or a folder of frames for an
//! animated one), recolored or used as drawn.

const kosm_icons = @import("kosm_icons");
const Cursor = @import("Cursor.zig");
const bibata_cursors = @import("bibata_cursors.zig");

/// The folder holding the SVGs, `~/...` or absolute: `<name>.svg` for each cursor, or
/// `<name>/<name>-01.svg` and on for an animated one.
directory: []const u8,
/// The cursors to build. Default: Bibata's, names, hotspots on a 256 unit canvas and frame
/// counts, so a folder drawn like Bibata needs nothing else.
cursors: []const Cursor = &bibata_cursors.left,
/// How the SVGs' colors change. null (default): used as drawn.
recolor: ?kosm_icons.Recolor = null,
