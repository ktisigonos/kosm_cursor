//! The XCursor file format: square premultiplied ARGB images, one or more per nominal size,
//! several of one size making an animation. What X apps and Wayland compositors load from a
//! theme's `cursors` folder.

const std = @import("std");

/// One image of a cursor file.
pub const Image = struct {
    /// The size it is picked for, in pixels; the image itself is `size` by `size`.
    size: u32,
    x_hotspot: u32,
    y_hotspot: u32,
    /// How long this frame shows, in milliseconds; 0 for a still cursor.
    delay: u32,
    /// `size * size` pixels, row by row: premultiplied `0xAARRGGBB`.
    pixels: []const u32,
};

const magic = "Xcur";
const file_header_size = 16;
const file_version = 0x10000;
const table_entry_size = 12;
const image_type = 0xfffd0002;
const image_header_size = 36;
const image_version = 1;

/// The file holding `images`, in order: frames of one size follow each other. The result lives
/// in `allocator`.
pub fn encode(allocator: std.mem.Allocator, images: []const Image) std.mem.Allocator.Error![]const u8 {
    var length: usize = file_header_size + table_entry_size * images.len;
    for (images) |image| {
        std.debug.assert(image.pixels.len == @as(usize, image.size) * image.size);
        length += image_header_size + 4 * image.pixels.len;
    }
    const bytes = try allocator.alloc(u8, length);
    var writer: std.Io.Writer = .fixed(bytes);
    write(&writer, images) catch unreachable; // the buffer was sized from the images
    std.debug.assert(writer.end == length);
    return bytes;
}

fn write(writer: *std.Io.Writer, images: []const Image) std.Io.Writer.Error!void {
    try writer.writeAll(magic);
    try writer.writeInt(u32, file_header_size, .little);
    try writer.writeInt(u32, file_version, .little);
    try writer.writeInt(u32, @intCast(images.len), .little);
    var position: usize = file_header_size + table_entry_size * images.len;
    for (images) |image| {
        try writer.writeInt(u32, image_type, .little);
        try writer.writeInt(u32, image.size, .little);
        try writer.writeInt(u32, @intCast(position), .little);
        position += image_header_size + 4 * image.pixels.len;
    }
    for (images) |image| {
        for ([_]u32{ image_header_size, image_type, image.size, image_version, image.size, image.size, image.x_hotspot, image.y_hotspot, image.delay }) |field|
            try writer.writeInt(u32, field, .little);
        try writer.writeSliceEndian(u32, image.pixels, .little);
    }
}

const testing = std.testing;

test "a file holds its header, one table entry per image and each image after the table" {
    const pixels = [_]u32{ 0xff000000, 0x80800000, 0x00000000, 0xffffffff };
    const bytes = try encode(testing.allocator, &.{
        .{ .size = 2, .x_hotspot = 1, .y_hotspot = 0, .delay = 40, .pixels = &pixels },
        .{ .size = 1, .x_hotspot = 0, .y_hotspot = 0, .delay = 40, .pixels = pixels[0..1] },
    });
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings("Xcur", bytes[0..4]);
    try testing.expectEqualSlices(u32, &.{ 16, file_version, 2 }, &words(bytes, 1, 3));
    // The second table entry: type, size 1, and its position after the first image's 36 + 16 bytes.
    try testing.expectEqualSlices(u32, &.{ image_type, 1, 40 + 36 + 16 }, &words(bytes, 7, 3));
    // The first image's header, then its pixels.
    try testing.expectEqualSlices(u32, &.{ 36, image_type, 2, 1, 2, 2, 1, 0, 40, 0xff000000, 0x80800000, 0, 0xffffffff }, &words(bytes, 10, 13));
    try testing.expectEqual(40 + 52 + 40, bytes.len);
}

/// `count` little-endian words of `bytes` from word `first` on.
fn words(bytes: []const u8, first: usize, comptime count: usize) [count]u32 {
    var result: [count]u32 = undefined;
    for (&result, first..) |*word, index| word.* = std.mem.readInt(u32, bytes[4 * index ..][0..4], .little);
    return result;
}
