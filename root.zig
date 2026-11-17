//! Cursors: a cursor theme in the kosmos' colors, for X apps, GTK, Qt and Hyprland.

const std = @import("std");

/// The cursor theme; build one with `from`.
pub const App = @import("App.zig");
/// Bibata in the theme's colors.
pub const from = App.from;
/// Bibata's style, hand and colors.
pub const Bibata = @import("Bibata.zig");
/// A theme of the user's own SVGs.
pub const Own = @import("Own.zig");
/// A theme installed on the system.
pub const System = @import("System.zig");
/// One cursor: its name, aliases, hotspot and frames.
pub const Cursor = @import("Cursor.zig");
/// Bibata's cursors, left- and right-handed, for an `Own` theme drawn like Bibata.
pub const bibata_cursors = @import("bibata_cursors.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    std.testing.refAllDecls(Bibata);
    std.testing.refAllDecls(@import("Picture.zig"));
    std.testing.refAllDecls(@import("xcursor.zig"));
    std.testing.refAllDecls(@import("zip.zig"));
    std.testing.refAllDecls(@import("hyprcursor.zig"));
}
