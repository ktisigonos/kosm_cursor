//! Hyprcursor's theme files: `manifest.hl` naming the theme, and per cursor a `.hlc` zip of its
//! SVGs with a `meta.hl` holding the hotspot, the other names and the frames. Hyprland draws
//! the SVGs itself at any size.

const std = @import("std");
const Cursor = @import("Cursor.zig");
const zip = @import("zip.zig");

/// The folder inside a theme holding the `.hlc` files.
pub const cursors_directory = "hyprcursors";

/// `manifest.hl` for a theme Hyprland picks by `name` (`HYPRCURSOR_THEME`).
pub fn manifest(allocator: std.mem.Allocator, name: []const u8, description: []const u8) std.mem.Allocator.Error![]const u8 {
    return allocator.print(
        \\name = {s}
        \\description = {s}
        \\version = 1
        \\cursors_directory = {s}
        \\
    , .{ name, description, cursors_directory });
}

/// One frame of a cursor, as stored in its `.hlc`.
pub const Frame = struct {
    /// The SVG's name inside the archive.
    name: []const u8,
    svg: []const u8,
};

/// The `.hlc` archive of `cursor`: its `meta.hl` and `frames`. The hotspot is a fraction of
/// the picture, 0..1 from the top left.
pub fn archive(allocator: std.mem.Allocator, cursor: Cursor, x_hotspot: f64, y_hotspot: f64, frames: []const Frame) error{ OutOfMemory, ArchiveTooLarge }![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    const writer = &text.writer;
    const delay: ?u32 = if (frames.len > 1) cursor.frame_delay else null;
    meta(writer, cursor, x_hotspot, y_hotspot, frames, delay) catch return error.OutOfMemory;
    const entries = try allocator.alloc(zip.Entry, frames.len + 1);
    entries[0] = .{ .name = "meta.hl", .content = text.written() };
    for (entries[1..], frames) |*entry, frame| entry.* = .{ .name = frame.name, .content = frame.svg };
    return zip.encode(allocator, entries);
}

fn meta(writer: *std.Io.Writer, cursor: Cursor, x_hotspot: f64, y_hotspot: f64, frames: []const Frame, delay: ?u32) std.Io.Writer.Error!void {
    // SVGs are drawn at the size asked for, so no resizing applies.
    try writer.print("resize_algorithm = none\nhotspot_x = {d:.4}\nhotspot_y = {d:.4}\n\n", .{ x_hotspot, y_hotspot });
    for (frames) |frame| {
        // Size 0 marks a picture drawn at any size.
        try writer.print("define_size = 0, {s}", .{frame.name});
        if (delay) |milliseconds| try writer.print(", {d}", .{milliseconds});
        try writer.writeByte('\n');
    }
    if (cursor.aliases.len != 0) try writer.writeByte('\n');
    for (cursor.aliases) |alias| try writer.print("define_override = {s}\n", .{alias});
}

const testing = std.testing;

test "an animated cursor's meta lists every frame with its delay and every alias" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var text: std.Io.Writer.Allocating = .init(arena.allocator());
    const cursor: Cursor = .{ .name = "wait", .x_hotspot = 128, .y_hotspot = 128, .aliases = &.{"watch"}, .frames = 2 };
    try meta(&text.writer, cursor, 0.5, 0.25, &.{ .{ .name = "wait-01.svg", .svg = "" }, .{ .name = "wait-02.svg", .svg = "" } }, 40);
    try testing.expectEqualStrings(
        \\resize_algorithm = none
        \\hotspot_x = 0.5000
        \\hotspot_y = 0.2500
        \\
        \\define_size = 0, wait-01.svg, 40
        \\define_size = 0, wait-02.svg, 40
        \\
        \\define_override = watch
        \\
    , text.written());
}

test "a still cursor's frame has no delay" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var text: std.Io.Writer.Allocating = .init(arena.allocator());
    try meta(&text.writer, .{ .name = "xterm", .x_hotspot = 0, .y_hotspot = 0 }, 0, 1, &.{.{ .name = "xterm.svg", .svg = "" }}, null);
    try testing.expectEqualStrings("resize_algorithm = none\nhotspot_x = 0.0000\nhotspot_y = 1.0000\n\ndefine_size = 0, xterm.svg\n", text.written());
}
