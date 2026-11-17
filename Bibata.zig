//! Bibata (ful1e5, GPL-3.0): compact, rounded or sharp Material cursors. Its sources draw
//! every cursor in three stand-in colors, which become `base`, `outline` and `watch`; the
//! wait spinner's segments and a few marks follow `rest`.

const Bibata = @This();

const std = @import("std");
const kosm = @import("kosm");
const kosm_icons = @import("kosm_icons");
const Recolor = kosm_icons.Recolor;
const Rgb = kosm_icons.svg.Rgb;

/// Rounded (`modern`) or sharp (`original`) edges. Default: `.modern`.
style: Style = .modern,
/// Which way the pointers lean. Default: `.left`, pointing up and left.
hand: Hand = .left,
/// Each cursor's body (Bibata Ice's white). Opaque. Default: the theme's foreground.
base: kosm.Color,
/// Each cursor's outline (Bibata Ice's black). Opaque. Default: the theme's background, opaque.
outline: kosm.Color,
/// The disc behind the wait spinner (Bibata Ice's white). Opaque. Default: the foreground.
watch: kosm.Color,
/// Every other color: the wait and progress spinners' four segments, and a few cursors'
/// marks. null keeps Bibata's own. Default: each becomes the palette hue it looks nearest.
/// One color for all: `.{ .theme = theme, .colors = .{ .roles = &.{.accent} }, .mode = .nearest }`.
rest: ?Recolor = null,

/// Bibata's two edge styles.
pub const Style = enum { modern, original };
/// Which way the pointers lean.
pub const Hand = enum { left, right };

/// Bibata Ice in the theme's colors: a foreground body on a background outline, and the
/// spinner in the palette.
pub fn from(theme: kosm.Theme) Bibata {
    var outline = theme.roles.background;
    outline.alpha = 1;
    return .{
        .base = theme.roles.foreground,
        .outline = outline,
        .watch = theme.roles.foreground,
        .rest = .{ .theme = theme, .colors = .all, .mode = .nearest },
    };
}

/// Bibata's folder of SVGs for this style and hand, inside its sources.
pub fn folder(set: Bibata) []const u8 {
    return switch (set.style) {
        .modern => if (set.hand == .left) "svg/modern" else "svg/modern-right",
        .original => if (set.hand == .left) "svg/original" else "svg/original-right",
    };
}

/// The color stand-in `rgb` of Bibata's sources stands for, or null for any other color.
pub fn standIn(set: Bibata, rgb: Rgb) ?kosm.Color {
    if (std.meta.eql(rgb, Rgb.hex("00ff00"))) return set.base;
    if (std.meta.eql(rgb, Rgb.hex("0000ff"))) return set.outline;
    if (std.meta.eql(rgb, Rgb.hex("ff0000"))) return set.watch;
    return null;
}

/// Why these colors cannot be drawn, or null: the stand-ins are opaque fills, and `rest`
/// must have colors to pick.
pub fn problem(set: Bibata) ?[]const u8 {
    if (set.base.alpha != 1 or set.outline.alpha != 1 or set.watch.alpha != 1)
        return "Bibata's base, outline and watch colors must be opaque (alpha 1)";
    if (set.rest) |rest| return rest.problem();
    return null;
}

const testing = std.testing;

test "the stand-ins map to their fields and every other color to none" {
    const theme: kosm.Theme = .from(.{ .palette = .{ .black = kosm.hex("101010"), .white = kosm.hex("f0f0f0") }, .mode = .dark });
    const set: Bibata = .from(theme);
    try testing.expectEqual(theme.roles.foreground, set.standIn(.hex("00ff00")).?);
    try testing.expectEqual(1, set.standIn(.hex("0000ff")).?.alpha);
    try testing.expectEqual(null, set.standIn(.hex("fe0000")));
}

test "a translucent stand-in color is a problem" {
    const theme: kosm.Theme = .from(.{ .palette = .{ .black = kosm.hex("101010"), .white = kosm.hex("f0f0f0") }, .mode = .dark });
    var set: Bibata = .from(theme);
    try testing.expectEqual(null, set.problem());
    set.outline.alpha = 0.5;
    try testing.expect(set.problem() != null);
}
