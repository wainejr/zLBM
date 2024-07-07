const std = @import("std");
const lbm = @import("lbm.zig");
const vtk = @import("vtk.zig");

fn writeArrayListToFile(filename: []const u8, list: *std.ArrayList(u8)) !void {
    // Open the file for writing
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // Get a writer for the file
    var writer = file.writer();

    // Write the contents of the ArrayList to the file
    try writer.writeAll(list.items);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const lbm_arrays = try lbm.allocate_arrs(&allocator);
    lbm_arrays.initialize();

    for (0..1000) |time_step| {
        std.debug.print("Running time step {}...\n", .{time_step});
        std.debug.print("rho {} ux {} uy {}...\n", .{ lbm_arrays.rho[0], lbm_arrays.ux[0], lbm_arrays.uy[0] });

        lbm.run_time_step(lbm_arrays, @intCast(time_step));
    }
    std.debug.print("Finished simulation!", .{});
    var rho_string = std.ArrayList(u8).init(allocator);
    try vtk.export_array(&rho_string, lbm_arrays.rho, &lbm.domain_size);
    try writeArrayListToFile("rho.vtk", &rho_string);
    var ux_string = std.ArrayList(u8).init(allocator);
    try vtk.export_array(&ux_string, lbm_arrays.ux, &lbm.domain_size);
    try writeArrayListToFile("ux.vtk", &ux_string);
    var uy_string = std.ArrayList(u8).init(allocator);
    try vtk.export_array(&uy_string, lbm_arrays.uy, &lbm.domain_size);
    try writeArrayListToFile("uy.vtk", &uy_string);

    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}
