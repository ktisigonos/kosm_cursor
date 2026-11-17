//! A cursor theme in the kosmos' colors, written whole to `directory` for X apps, GTK and Qt
//! (XCursor) and for Hyprland (hyprcursor), or a theme installed on the system picked by name.
//! GTK and Hyprland pick it by `themeName`.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");
const kosm_icons = @import("kosm_icons");
const sources = @import("sources");
const Bibata = @import("Bibata.zig");
const Own = @import("Own.zig");
const System = @import("System.zig");
const Cursor = @import("Cursor.zig");
const Picture = @import("Picture.zig");
const bibata_cursors = @import("bibata_cursors.zig");
const hyprcursor = @import("hyprcursor.zig");
const xcursor = @import("xcursor.zig");
const svg = kosm_icons.svg;
const Recolor = kosm_icons.Recolor;

/// Which cursors: Bibata in the theme's colors, the user's own SVGs, or a theme installed on
/// the system. null: nothing is written and no cursor theme is picked. Default (`from`): Bibata.
cursors: ?Cursors = null,
/// The folder a generated theme is written to, `~/...` or absolute; its name is the name
/// programs pick the theme by. Files a former apply wrote there and this one doesn't are left.
/// Default: `~/.local/share/icons/kosm_cursor`.
directory: []const u8 = "~/.local/share/icons/kosm_cursor",
/// The name cursor pickers show for a generated theme (`Name` in its index.theme). null
/// (default): the theme's `name`, or the name kosm applies the kosmos under.
name: ?[]const u8 = null,
/// The pixel sizes XCursor files hold, each drawn from the SVGs; programs asking for another
/// size get the nearest. Hyprcursor draws any size itself. Default: Bibata's, 16 to 96.
sizes: []const u32 = &default_sizes,
/// The size Hyprland is told to show the cursor at after an apply (`hyprctl setcursor`), so it
/// loads the new cursors at once. null (default): Hyprland is not told and loads them when it
/// next starts.
size: ?u32 = null,

/// The cursors an app writes or picks.
pub const Cursors = union(enum) {
    /// Bibata, recolored into `directory`.
    bibata: Bibata,
    /// The user's own SVGs, recolored or not, into `directory`.
    own: Own,
    /// A theme installed on the system, used as is.
    system: System,
};

const default_sizes = [_]u32{ 16, 20, 22, 24, 28, 32, 40, 48, 56, 64, 72, 80, 88, 96 };

/// Bibata in the theme's colors.
pub fn from(theme: kosm.Theme) App {
    return .{ .cursors = .{ .bibata = .from(theme) }, .name = theme.name };
}

/// The name programs pick the cursor theme by: `directory`'s last folder for a generated
/// theme, the system theme's own name, null with no `cursors`.
pub fn themeName(self: App) ?[]const u8 {
    const cursors = self.cursors orelse return null;
    if (cursors == .system) return cursors.system.name;
    return std.Io.Dir.path.basename(self.directory);
}

/// Writes the generated theme, if any, as one group in diffs: `index.theme`, an XCursor file
/// per cursor in `cursors/` with a link per alias, and hyprcursor's `manifest.hl` and
/// `hyprcursors/`.
pub fn apply(self: App, output: *kosm.Output) !void {
    const cursors = self.cursors orelse return;
    const source: Source = switch (cursors) {
        .system => return,
        .bibata => |set| .{
            .folder = try std.Io.Dir.path.join(output.allocator, &.{ sources.bibata, set.folder() }),
            .cursors = if (set.hand == .left) &bibata_cursors.left else &bibata_cursors.right,
            .coloring = .{ .bibata = set },
        },
        .own => |own| .{
            .folder = own.directory,
            .cursors = own.cursors,
            .coloring = if (own.recolor) |recolor| .{ .recolor = recolor } else .keep,
        },
    };
    if (self.sourceProblem(source)) |problem| return output.fail(self.directory, "{s}", .{problem});
    try self.generate(output, source);
}

/// Tells Hyprland to load the cursors at `size`; a failure (Hyprland not running) is a warning.
pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    const size = self.size orelse return;
    const name = self.themeName() orelse return;
    var buffer: [16]u8 = undefined;
    const printed = std.fmt.bufPrint(&buffer, "{d}", .{size}) catch unreachable; // a u32 fits
    try reloader.run(&.{ "hyprctl", "setcursor", name, printed });
}

/// Where a generated theme's SVGs come from and what their colors become.
const Source = struct {
    folder: []const u8,
    cursors: []const Cursor,
    coloring: Coloring,
};

const Coloring = union(enum) {
    bibata: Bibata,
    recolor: Recolor,
    keep,
};

fn sourceProblem(self: App, source: Source) ?[]const u8 {
    if (self.sizes.len == 0) return "sizes is empty: XCursor files need at least one size";
    if (std.mem.indexOfScalar(u32, self.sizes, 0) != null) return "sizes holds 0: every size must be at least one pixel";
    if (source.cursors.len == 0) return "the theme has no cursors";
    return switch (source.coloring) {
        .bibata => |set| set.problem(),
        .recolor => |recolor| recolor.problem(),
        .keep => null,
    };
}

fn generate(self: App, output: *kosm.Output, source: Source) !void {
    const allocator = output.allocator;
    const group = self.directory;
    const theme_name = self.themeName().?;
    const display_name = try output.displayName(self.directory, self.name);
    try output.verbatim(.{
        .file = try self.path(output, &.{"index.theme"}),
        .content = try allocator.print("[Icon Theme]\nName={s}\nComment=Cursors made by kosm\n", .{display_name}),
        .group = group,
    });
    try output.verbatim(.{
        .file = try self.path(output, &.{"manifest.hl"}),
        .content = try hyprcursor.manifest(allocator, theme_name, display_name),
        .group = group,
    });
    var colors: Colors = .{ .allocator = allocator, .coloring = source.coloring };
    for (source.cursors) |cursor| try self.writeCursor(output, source.folder, cursor, &colors);
}

/// Writes one cursor's XCursor file, its links and its `.hlc`.
fn writeCursor(self: App, output: *kosm.Output, folder: []const u8, cursor: Cursor, colors: *Colors) !void {
    const allocator = output.allocator;
    const group = self.directory;
    if (cursor.frames == 0) return output.fail(self.directory, "cursor {s} has 0 frames", .{cursor.name});
    const frames = try allocator.alloc(hyprcursor.Frame, cursor.frames);
    const pictures = try allocator.alloc(Picture, cursor.frames);
    var parsed: usize = 0;
    defer for (pictures[0..parsed]) |picture| picture.deinit();
    for (frames, pictures, 1..) |*frame, *picture, number| {
        const relative = if (cursor.frames == 1)
            try allocator.print("{s}.svg", .{cursor.name})
        else
            try allocator.print("{s}/{s}-{d:0>2}.svg", .{ cursor.name, cursor.name, number });
        const file = try std.Io.Dir.path.join(allocator, &.{ folder, relative });
        frame.* = .{ .name = std.Io.Dir.path.basename(relative), .svg = try colors.recolorSvg(try output.read(file)) };
        picture.* = Picture.parse(frame.svg) catch |err| return output.fail(file, "{s}", .{Picture.describe(err)});
        parsed += 1;
    }

    const canvas = @max(pictures[0].width, pictures[0].height);
    const archive = hyprcursor.archive(allocator, cursor, cursor.x_hotspot / canvas, cursor.y_hotspot / canvas, frames) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ArchiveTooLarge => return output.fail(self.directory, "cursor {s} is too large for a zip archive", .{cursor.name}),
    };
    const archive_name = try allocator.print("{s}.hlc", .{cursor.name});
    try output.verbatim(.{ .file = try self.path(output, &.{ hyprcursor.cursors_directory, archive_name }), .content = archive, .group = group });

    const images = try allocator.alloc(xcursor.Image, self.sizes.len * pictures.len);
    for (self.sizes, 0..) |size, size_index| {
        for (pictures, 0..) |picture, frame_index| {
            const scale = picture.scaleTo(size);
            images[size_index * pictures.len + frame_index] = .{
                .size = size,
                .x_hotspot = hotspotPixel(cursor.x_hotspot * scale, size),
                .y_hotspot = hotspotPixel(cursor.y_hotspot * scale, size),
                .delay = if (pictures.len > 1) cursor.frame_delay else 0,
                .pixels = try picture.render(allocator, size),
            };
        }
    }
    try output.verbatim(.{ .file = try self.path(output, &.{ "cursors", cursor.name }), .content = try xcursor.encode(allocator, images), .group = group });
    for (cursor.aliases) |alias|
        try output.link(.{ .file = try self.path(output, &.{ "cursors", alias }), .target = cursor.name, .group = group });
}

/// The pixel a hotspot at `position` pixels falls on, inside a `size` square.
fn hotspotPixel(position: f64, size: u32) u32 {
    const pixel: u32 = @intFromFloat(std.math.clamp(@round(position), 0, @as(f64, @floatFromInt(size - 1))));
    return pixel;
}

fn path(self: App, output: *kosm.Output, parts: []const []const u8) ![]const u8 {
    const joined = try std.Io.Dir.path.join(output.allocator, parts);
    return std.Io.Dir.path.join(output.allocator, &.{ self.directory, joined });
}

/// Recolors SVGs, converting each distinct color once.
const Colors = struct {
    allocator: std.mem.Allocator,
    coloring: Coloring,
    cache: std.AutoHashMapUnmanaged(svg.Rgb, svg.Rgb) = .empty,

    fn recolorSvg(colors: *Colors, content: []const u8) ![]const u8 {
        if (colors.coloring == .keep) return content;
        const scanned = try svg.scan(colors.allocator, content);
        if (scanned.tokens.len == 0) return content;
        const replaced = try colors.allocator.alloc(svg.Rgb, scanned.tokens.len);
        for (scanned.tokens, replaced) |token, *color| color.* = try colors.single(token.rgb);
        return svg.rewrite(colors.allocator, content, scanned, replaced);
    }

    fn single(colors: *Colors, rgb: svg.Rgb) !svg.Rgb {
        const entry = try colors.cache.getOrPut(colors.allocator, rgb);
        if (!entry.found_existing) entry.value_ptr.* = colors.convert(rgb);
        return entry.value_ptr.*;
    }

    fn convert(colors: *const Colors, rgb: svg.Rgb) svg.Rgb {
        const rule = switch (colors.coloring) {
            .bibata => |set| if (set.standIn(rgb)) |color| return toRgb(color) else set.rest orelse return rgb,
            .recolor => |recolor| recolor,
            .keep => return rgb,
        };
        return toRgb(rule.apply(fromRgb(rgb)));
    }
};

fn fromRgb(rgb: svg.Rgb) kosm.Color {
    return .fromRgb(.{ .red = channel(rgb.red), .green = channel(rgb.green), .blue = channel(rgb.blue), .alpha = 1 });
}

fn channel(value: u8) f64 {
    return @as(f64, @floatFromInt(value)) / 255;
}

/// `color` clipped to sRGB as kosm prints colors.
fn toRgb(color: kosm.Color) svg.Rgb {
    const text = color.hex();
    const digits = text.slice()[1..7];
    return .{ .red = hexByte(digits[0..2]), .green = hexByte(digits[2..4]), .blue = hexByte(digits[4..6]) };
}

fn hexByte(digits: []const u8) u8 {
    return std.fmt.parseInt(u8, digits, 16) catch unreachable; // Color.hex prints two hex digits a channel
}

const testing = std.testing;

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io), .warnings = undefined, .output = undefined };
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "cursor",
            .kosmos = "frost",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn write(fixture: *Fixture, file: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(file)) |folder| try fixture.tmp.dir.createDirPath(testing.io, folder);
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = file, .data = data });
    }

    fn planned(fixture: *Fixture, display_path: []const u8) []const u8 {
        const file = fixture.plan.find(fixture.absolute(display_path)) orelse return "(not planned)";
        return file.new;
    }

    fn linked(fixture: *Fixture, display_path: []const u8) []const u8 {
        const link = fixture.plan.findLink(fixture.absolute(display_path)) orelse return "(not planned)";
        return link.target;
    }

    fn absolute(fixture: *Fixture, display_path: []const u8) []const u8 {
        return std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.output.home, display_path[2..] }) catch @panic("OOM");
    }
};

const test_palette: kosm.Palette = .{ .black = kosm.hex("101010"), .white = kosm.hex("f0f0f0"), .blue = kosm.hex("5e81ac"), .red = kosm.hex("bf616a") };

/// A 4 unit square: the left half in `#00ff00`, the right in `#ff0000`.
const test_svg =
    \\<svg width="4" height="4" xmlns="http://www.w3.org/2000/svg"><rect width="2" height="4" fill="#00ff00"/><rect x="2" width="2" height="4" fill="#ff0000"/></svg>
;

/// Little-endian word `index` of `bytes`.
fn word(bytes: []const u8, index: usize) u32 {
    return std.mem.readInt(u32, bytes[4 * index ..][0..4], .little);
}

test "own SVGs become XCursor files with links and hyprcursor archives, recolored, as one group" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.write("svgs/left_ptr.svg", test_svg);
    try fixture.write("svgs/wait/wait-01.svg", test_svg);
    try fixture.write("svgs/wait/wait-02.svg", test_svg);
    const theme: kosm.Theme = .from(.{ .palette = test_palette, .mode = .dark });
    const app: App = .{
        .cursors = .{ .own = .{
            .directory = fixture.absolute("~/svgs"),
            .cursors = &.{
                .{ .name = "left_ptr", .x_hotspot = 1, .y_hotspot = 3, .aliases = &.{ "default", "arrow" } },
                .{ .name = "wait", .x_hotspot = 2, .y_hotspot = 2, .frames = 2, .frame_delay = 30 },
            },
            .recolor = .{ .theme = theme, .colors = .{ .only = &.{kosm.hex("0000ff")} }, .mode = .nearest, .grays = .match },
        } },
        .directory = "~/icons/kosm_cursor",
        .sizes = &.{ 2, 4 },
    };
    try app.apply(&fixture.output);

    try testing.expectEqualStrings("[Icon Theme]\nName=frost\nComment=Cursors made by kosm\n", fixture.planned("~/icons/kosm_cursor/index.theme"));
    try testing.expect(std.mem.startsWith(u8, fixture.planned("~/icons/kosm_cursor/manifest.hl"), "name = kosm_cursor\n"));
    try testing.expectEqualStrings("left_ptr", fixture.linked("~/icons/kosm_cursor/cursors/default"));
    try testing.expectEqualStrings("left_ptr", fixture.linked("~/icons/kosm_cursor/cursors/arrow"));

    // Sizes 2 and 4, hotspot (1, 3) in a 4 unit SVG: at size 2, (0.5, 1.5) rounds to (1, 2),
    // which stays inside the 2 pixel square as (1, 1).
    const pointer = fixture.planned("~/icons/kosm_cursor/cursors/left_ptr");
    try testing.expectEqual(2, word(pointer, 3));
    const first_image = word(pointer, 6) / 4;
    try testing.expectEqualSlices(u32, &.{ 2, 1, 1, 0 }, &.{ word(pointer, first_image + 4), word(pointer, first_image + 6), word(pointer, first_image + 7), word(pointer, first_image + 8) });
    // Every color became blue: the first pixel is opaque blue.
    try testing.expectEqual(0xff0000ff, word(pointer, first_image + 9));

    // Two sizes of two frames, each frame showing 30 ms.
    const wait = fixture.planned("~/icons/kosm_cursor/cursors/wait");
    try testing.expectEqual(4, word(wait, 3));
    try testing.expectEqual(30, word(wait, word(wait, 6) / 4 + 8));

    const archive = fixture.planned("~/icons/kosm_cursor/hyprcursors/wait.hlc");
    try testing.expect(std.mem.indexOf(u8, archive, "hotspot_x = 0.5000\nhotspot_y = 0.5000\n") != null);
    try testing.expect(std.mem.indexOf(u8, archive, "define_size = 0, wait-02.svg, 30\n") != null);
    try testing.expect(std.mem.indexOf(u8, archive, "fill=\"#0000ff\"") != null);
    try testing.expect(std.mem.indexOf(u8, archive, "#00ff00") == null);

    const groups = try fixture.plan.changedGroups(testing.allocator);
    defer testing.allocator.free(groups);
    try testing.expectEqual(1, groups.len);
    try testing.expectEqualStrings("kosm_cursor", app.themeName().?);
}

test "Bibata's stand-ins become the set's colors and its other colors follow rest" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var colors: Colors = .{ .allocator = arena.allocator(), .coloring = .{ .bibata = .{
        .base = kosm.hex("111111"),
        .outline = kosm.hex("222222"),
        .watch = kosm.hex("333333"),
    } } };
    try testing.expectEqualStrings(
        "<path fill=\"#111111\" stroke=\"#222222\"/><circle fill=\"#333333\"/><path fill=\"#f05024\"/>",
        try colors.recolorSvg("<path fill=\"#00FF00\" stroke=\"#0000FF\"/><circle fill=\"#FF0000\"/><path fill=\"#F05024\"/>"),
    );
}

test "the bundled Bibata is written whole: every cursor, its links and archives" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app: App = .from(.from(.{ .palette = test_palette, .mode = .dark }));
    app.sizes = &.{8};
    try app.apply(&fixture.output);
    try testing.expectEqual(2 + 2 * bibata_cursors.left.len, fixture.plan.files.items.len);
    try testing.expect(fixture.plan.links.items.len > 50);
    try testing.expectEqualStrings("left_ptr", fixture.linked("~/.local/share/icons/kosm_cursor/cursors/default"));
    // The default body is the theme's foreground: no stand-in is left.
    try testing.expect(std.mem.indexOf(u8, fixture.planned("~/.local/share/icons/kosm_cursor/hyprcursors/left_ptr.hlc"), "#00FF00") == null);
}

test "a file that is no SVG fails naming it, and a missing one fails" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.write("svgs/left_ptr.svg", "<html/>");
    const broken: App = .{ .cursors = .{ .own = .{ .directory = fixture.absolute("~/svgs"), .cursors = &.{.{ .name = "left_ptr", .x_hotspot = 0, .y_hotspot = 0 }} } } };
    try testing.expectError(error.AppFailed, broken.apply(&fixture.output));
    try testing.expect(std.mem.endsWith(u8, fixture.diagnostics.file, "svgs/left_ptr.svg"));
    const missing: App = .{ .cursors = .{ .own = .{ .directory = fixture.absolute("~/svgs"), .cursors = &.{.{ .name = "xterm", .x_hotspot = 0, .y_hotspot = 0 }} } }, .directory = "~/other" };
    try testing.expectError(error.ReadFailed, missing.apply(&fixture.output));
}

test "a translucent Bibata color or no sizes fail before anything is written" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var app: App = .from(.from(.{ .palette = test_palette, .mode = .dark }));
    app.cursors.?.bibata.base.alpha = 0.5;
    try testing.expectError(error.AppFailed, app.apply(&fixture.output));
    app = .from(.from(.{ .palette = test_palette, .mode = .dark }));
    app.sizes = &.{};
    try testing.expectError(error.AppFailed, app.apply(&fixture.output));
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

test "a system theme writes nothing and is picked by its own name" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{ .cursors = .{ .system = .{ .name = "Bibata-Modern-Ice" } } };
    try app.apply(&fixture.output);
    try testing.expectEqual(0, fixture.plan.files.items.len);
    try testing.expectEqualStrings("Bibata-Modern-Ice", app.themeName().?);
    try testing.expectEqual(null, (App{}).themeName());
}
