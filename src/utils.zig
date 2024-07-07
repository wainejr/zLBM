const std = @import("std");

pub fn writeArrayListToFile(filename: []const u8, list: *std.ArrayList(u8)) !void {
    // Open the file for writing
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // Get a writer for the file
    var writer = file.writer();

    // Write the contents of the ArrayList to the file
    try writer.writeAll(list.items);
}
