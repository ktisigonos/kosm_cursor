//! One cursor of a theme: the name programs ask for, the other names it answers to, its
//! hotspot and, for an animated cursor, its frames.

const Cursor = @This();

/// The cursor's name (`left_ptr`), its SVG's name: `<name>.svg`, or for an animated cursor
/// `<name>/<name>-01.svg`, `<name>/<name>-02.svg` and so on.
name: []const u8,
/// The pixel it points with, from the SVG's left edge, in the SVG's own units.
x_hotspot: f64,
/// The pixel it points with, from the SVG's top edge, in the SVG's own units.
y_hotspot: f64,
/// Other names programs ask for it by (`default`, `arrow`): XCursor links and hyprcursor
/// overrides. Default: none.
aliases: []const []const u8 = &.{},
/// How many frames an animated cursor has, 1 for a still one. Default: 1.
frames: u32 = 1,
/// How long each frame of an animated cursor shows, in milliseconds. Default: 40.
frame_delay: u32 = 40,
