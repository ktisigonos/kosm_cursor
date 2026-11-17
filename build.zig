const std = @import("std");

pub fn build(b: *std.Build) void {
    const module = @import("kosm").packageModule(b) orelse return;
    const bibata = b.dependency("bibata", .{});
    const options = b.addOptions();
    options.addOption([]const u8, "bibata", bibataPath(b, bibata));
    module.addOptions("sources", options);
    // resvg draws the SVGs into XCursor's pixels.
    module.link_libc = true;
    module.linkSystemLibrary("resvg", .{});
}

/// Bibata's absolute folder: the app reads it when a kosmos is applied, from wherever that runs.
fn bibataPath(b: *std.Build, bibata: *std.Build.Dependency) []const u8 {
    const path = bibata.builder.root.joinString(b.allocator, ".") catch @panic("OOM");
    return std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, path, b.allocator) catch |err|
        std.debug.panic("cannot find Bibata's folder {s}: {s}", .{ path, @errorName(err) });
}
