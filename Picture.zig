//! An SVG parsed by resvg, ready to render at any size. Owns resvg's tree; `deinit` frees it.

const Picture = @This();

const std = @import("std");

tree: *resvg.Tree,
/// The SVG's own width and height, in its units.
width: f64,
height: f64,

/// Errors from parsing an SVG; `Picture.describe` names each.
pub const ParseError = error{ NotUtf8, InvalidSize, InvalidSvg, TooManyElements };

/// Parses `text`, an SVG document.
pub fn parse(text: []const u8) ParseError!Picture {
    const options = resvg.resvg_options_create() orelse return error.InvalidSvg;
    defer resvg.resvg_options_destroy(options);
    var tree: ?*resvg.Tree = null;
    const code = resvg.resvg_parse_tree_from_data(text.ptr, text.len, options, &tree);
    switch (code) {
        resvg.ok => {},
        resvg.not_utf8 => return error.NotUtf8,
        resvg.elements_limit_reached => return error.TooManyElements,
        resvg.invalid_size => return error.InvalidSize,
        else => return error.InvalidSvg,
    }
    const parsed = tree orelse return error.InvalidSvg;
    const size = resvg.resvg_get_image_size(parsed);
    return .{ .tree = parsed, .width = size.width, .height = size.height };
}

/// What a parse error means, for a message.
pub fn describe(err: ParseError) []const u8 {
    return switch (err) {
        error.NotUtf8 => "is not UTF-8",
        error.InvalidSize => "has no valid size: width and height, or a viewBox, must be above 0",
        error.InvalidSvg => "is not a valid SVG",
        error.TooManyElements => "has more than a million elements",
    };
}

pub fn deinit(picture: Picture) void {
    resvg.resvg_tree_destroy(picture.tree);
}

/// The picture drawn into a `size` by `size` square, scaled so its longer side fills it, from
/// the top left: `size * size` premultiplied `0xAARRGGBB` pixels, row by row, owned by the
/// caller.
pub fn render(picture: Picture, allocator: std.mem.Allocator, size: u32) std.mem.Allocator.Error![]u32 {
    const count = @as(usize, size) * size;
    const rgba = try allocator.alloc(u8, 4 * count);
    defer allocator.free(rgba);
    // resvg draws over what the buffer holds.
    @memset(rgba, 0);
    const scale: f32 = @floatCast(picture.scaleTo(size));
    resvg.resvg_render(picture.tree, .{ .a = scale, .b = 0, .c = 0, .d = scale, .e = 0, .f = 0 }, size, size, rgba.ptr);
    const pixels = try allocator.alloc(u32, count);
    for (pixels, 0..) |*pixel, index| {
        const channels = rgba[4 * index ..][0..4];
        pixel.* = @as(u32, channels[3]) << 24 | @as(u32, channels[0]) << 16 | @as(u32, channels[1]) << 8 | channels[2];
    }
    return pixels;
}

/// How much `render` scales the picture's units to fill `size` pixels.
pub fn scaleTo(picture: Picture, size: u32) f64 {
    return @as(f64, @floatFromInt(size)) / @max(picture.width, picture.height);
}

/// resvg's C API (`resvg.h`), only the calls kosm makes.
const resvg = struct {
    const Options = opaque {};
    const Tree = opaque {};
    const Transform = extern struct { a: f32, b: f32, c: f32, d: f32, e: f32, f: f32 };
    const Size = extern struct { width: f32, height: f32 };

    const ok = 0;
    const not_utf8 = 1;
    const elements_limit_reached = 5;
    const invalid_size = 6;

    extern fn resvg_options_create() ?*Options;
    extern fn resvg_options_destroy(options: *Options) void;
    extern fn resvg_parse_tree_from_data(data: [*]const u8, len: usize, options: *const Options, tree: *?*Tree) i32;
    extern fn resvg_tree_destroy(tree: *Tree) void;
    extern fn resvg_get_image_size(tree: *const Tree) Size;
    extern fn resvg_render(tree: *const Tree, transform: Transform, width: u32, height: u32, pixmap: [*]u8) void;
};

const testing = std.testing;

test "a square SVG renders scaled to the size, premultiplied ARGB, the rest transparent" {
    const picture = try parse(
        \\<svg width="4" height="4" xmlns="http://www.w3.org/2000/svg">
        \\<rect width="2" height="4" fill="#ff0000"/><rect x="2" width="2" height="2" fill="#0000ff" fill-opacity="0.5"/>
        \\</svg>
    );
    defer picture.deinit();
    try testing.expectEqual(4, picture.width);
    const pixels = try picture.render(testing.allocator, 2);
    defer testing.allocator.free(pixels);
    try testing.expectEqual(0xffff0000, pixels[0]);
    try testing.expectEqual(0xffff0000, pixels[2]);
    // Half-transparent blue, premultiplied: alpha and blue both about 0x80.
    try testing.expect(pixels[1] >> 24 >= 0x7f and pixels[1] >> 24 <= 0x80 and pixels[1] & 0xff == pixels[1] >> 24);
    try testing.expectEqual(0, pixels[3]);
}

test "a wide SVG fills the square's width" {
    const picture = try parse("<svg width=\"8\" height=\"4\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"8\" height=\"4\" fill=\"#fff\"/></svg>");
    defer picture.deinit();
    try testing.expectEqual(0.25, picture.scaleTo(2));
}

test "text that is no SVG fails to parse" {
    try testing.expectError(error.InvalidSvg, parse("<html/>"));
    try testing.expectError(error.InvalidSvg, parse("not xml"));
}
