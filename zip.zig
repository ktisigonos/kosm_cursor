//! Writes zip archives of files stored uncompressed, as hyprcursor's `.hlc` cursor files are.
//! Every entry is dated 1980-01-01, the earliest date zip can hold, so the same files always
//! give the same bytes and an unchanged cursor is not rewritten.

const std = @import("std");

/// One file in an archive.
pub const Entry = struct {
    /// The file's name inside the archive, `/` between folders.
    name: []const u8,
    content: []const u8,
};

const local_header_signature = 0x04034b50;
const central_header_signature = 0x02014b50;
const end_signature = 0x06054b50;
const local_header_size = 30;
const central_header_size = 46;
const end_size = 22;
/// Zip 1.0, enough for stored entries.
const version_needed = 10;
const method_stored = 0;
/// 1980-01-01 in MS-DOS date bits: years since 1980, month, day.
const dos_date = (0 << 9) | (1 << 5) | 1;
const dos_time = 0;

/// The archive of `entries`, in order. The result lives in `allocator`. Archives over 4 GiB
/// or 65535 entries, which need zip64, are an error.
pub fn encode(allocator: std.mem.Allocator, entries: []const Entry) error{ OutOfMemory, ArchiveTooLarge }![]const u8 {
    var length: usize = end_size;
    for (entries) |entry| length += local_header_size + central_header_size + 2 * entry.name.len + entry.content.len;
    if (length > std.math.maxInt(u32) or entries.len > std.math.maxInt(u16)) return error.ArchiveTooLarge;
    const bytes = try allocator.alloc(u8, length);
    var writer: std.Io.Writer = .fixed(bytes);
    write(&writer, entries) catch unreachable; // the buffer was sized from the entries
    std.debug.assert(writer.end == length);
    return bytes;
}

fn write(writer: *std.Io.Writer, entries: []const Entry) std.Io.Writer.Error!void {
    var offset: u32 = 0;
    for (entries) |entry| {
        try writer.writeInt(u32, local_header_signature, .little);
        try writeCommon(writer, entry);
        try writer.writeInt(u16, 0, .little); // extra field length
        try writer.writeAll(entry.name);
        try writer.writeAll(entry.content);
    }
    const directory_start: u32 = @intCast(writer.end);
    for (entries) |entry| {
        try writer.writeInt(u32, central_header_signature, .little);
        try writer.writeInt(u16, version_needed, .little); // version made by: MS-DOS, zip 1.0
        try writeCommon(writer, entry);
        for ([_]u16{ 0, 0, 0, 0 }) |field| try writer.writeInt(u16, field, .little); // extra, comment, disk, internal attributes
        try writer.writeInt(u32, 0, .little); // external attributes
        try writer.writeInt(u32, offset, .little);
        try writer.writeAll(entry.name);
        offset += @intCast(local_header_size + entry.name.len + entry.content.len);
    }
    const directory_size: u32 = @intCast(writer.end - directory_start);
    try writer.writeInt(u32, end_signature, .little);
    for ([_]u16{ 0, 0, @intCast(entries.len), @intCast(entries.len) }) |field| try writer.writeInt(u16, field, .little);
    try writer.writeInt(u32, directory_size, .little);
    try writer.writeInt(u32, directory_start, .little);
    try writer.writeInt(u16, 0, .little); // comment length
}

/// The fields local and central headers share, from "version needed" to the name's length.
fn writeCommon(writer: *std.Io.Writer, entry: Entry) std.Io.Writer.Error!void {
    for ([_]u16{ version_needed, 0, method_stored, dos_time, dos_date }) |field| try writer.writeInt(u16, field, .little);
    try writer.writeInt(u32, std.hash.Crc32.hash(entry.content), .little);
    try writer.writeInt(u32, @intCast(entry.content.len), .little);
    try writer.writeInt(u32, @intCast(entry.content.len), .little);
    try writer.writeInt(u16, @intCast(entry.name.len), .little);
}

const testing = std.testing;

test "an archive reads back through std's zip reader, every file intact" {
    const entries = [_]Entry{
        .{ .name = "meta.hl", .content = "hotspot_x = 0.5\n" },
        .{ .name = "left_ptr.svg", .content = "<svg/>" },
        .{ .name = "empty", .content = "" },
    };
    const bytes = try encode(testing.allocator, &entries);
    defer testing.allocator.free(bytes);

    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "cursor.hlc", .data = bytes });
    const file = try tmp.dir.openFile(testing.io, "cursor.hlc", .{});
    defer file.close(testing.io);
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(testing.io, &buffer);
    try tmp.dir.createDirPath(testing.io, "out");
    var out = try tmp.dir.openDir(testing.io, "out", .{});
    defer out.close(testing.io);
    try std.zip.extract(out, &reader, .{});
    for (entries) |entry| {
        const content = try out.readFileAlloc(testing.io, entry.name, testing.allocator, .limited(1024));
        defer testing.allocator.free(content);
        try testing.expectEqualStrings(entry.content, content);
    }
}

test "the same files give the same bytes" {
    const entries = [_]Entry{.{ .name = "a", .content = "b" }};
    const first = try encode(testing.allocator, &entries);
    defer testing.allocator.free(first);
    const second = try encode(testing.allocator, &entries);
    defer testing.allocator.free(second);
    try testing.expectEqualSlices(u8, first, second);
}
