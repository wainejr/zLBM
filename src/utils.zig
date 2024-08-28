const std = @import("std");

pub fn writeArrayListToFile(filename: []const u8, content: []const u8) !void {
    // Open the file for writing
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // Get a writer for the file
    var writer = file.writer();

    // Write the contents of the ArrayList to the file
    try writer.writeAll(content);
}

// Function to append formatted strings to the list
pub fn appendFormatted(list: *std.ArrayList(u8), comptime format_string: []const u8, args: anytype) !void {
    var buffer: [512]u8 = undefined;
    const buffer_slice = buffer[0..];

    const str_add = try std.fmt.bufPrint(buffer_slice, format_string, args);

    try list.appendSlice(str_add);
}
