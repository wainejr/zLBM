const std = @import("std");
const utils = @import("utils.zig");

fn write_vtk_header(vtk_string: *std.ArrayList(u8), dims: []const u32) !void {
    const dims_use: [3]u32 = .{ dims[0], dims[1], if (dims.len < 3) 1 else dims[2] };

    try vtk_string.appendSlice("# vtk DataFile Version 3.0\nData\nBINARY\nDATASET STRUCTURED_POINTS\n");

    // "DIMENSIONS "+to_string(Nx)+" "+to_string(Ny)+" "+to_string(Nz)+"\n"
    try vtk_string.appendSlice("DIMENSIONS ");
    for (dims_use) |d| {
        try utils.appendFormatted(vtk_string, "{} ", .{d});
    }
    try vtk_string.appendSlice("\n");
    // "ORIGIN "+to_string(origin.x)+" "+to_string(origin.y)+" "+to_string(origin.z)+"\n"
    try vtk_string.appendSlice("ORIGIN ");
    for (dims_use) |_| {
        try utils.appendFormatted(vtk_string, "{} ", .{0});
    }
    try vtk_string.appendSlice("\n");
    // "SPACING "+to_string(spacing)+" "+to_string(spacing)+" "+to_string(spacing)+"\n"
    try vtk_string.appendSlice("SPACING ");
    for (dims_use) |_| {
        try utils.appendFormatted(vtk_string, "{} ", .{1});
    }
    try vtk_string.appendSlice("\n");
    // "POINT_DATA "+to_string((ulong)Nx*(ulong)Ny*(ulong)Nz)+
    try utils.appendFormatted(vtk_string, "POINT_DATA {}", .{dims_use[0] * dims_use[1] * dims_use[2]});
    // "\nSCALARS data "+vtk_type()+" "+to_string(dimensions())+"\nLOOKUP_TABLE default\n"
}

fn write_vtk_data(vtk_string: *std.ArrayList(u8), scalar_name: []const u8, arr: []const f32) !void {
    try utils.appendFormatted(vtk_string, "\nSCALARS {s} float 1", .{scalar_name});
    // std.debug.print("my string {s}\n", .{vtk_string.items});
    try vtk_string.appendSlice("\nLOOKUP_TABLE default\n");

    // Write the scalar data in big-endian format
    var be_scalar: [4]u8 = undefined;
    for (arr) |value| {
        be_scalar = @bitCast(value);
        // std.debug.print("value {} bits {b:0>32} rev {b:0>32} scalars {x:} {x:} {x:} {x:}\n", .{ value, be_value, be_rev, be_scalar[0], be_scalar[1], be_scalar[2], be_scalar[3] });
        const be_use: [4]u8 = .{ be_scalar[3], be_scalar[2], be_scalar[1], be_scalar[0] };
        try vtk_string.appendSlice(be_use[0..4]);
    }
}

pub fn write_vtk(vtk_string: *std.ArrayList(u8), kv_arr: std.StringArrayHashMap([]const f32), dims: []const u32) !void {
    try write_vtk_header(vtk_string, dims);

    var arr_size: usize = 1;
    for (dims) |d| {
        arr_size *= d;
    }

    var it = kv_arr.iterator();
    while (it.next()) |entry| {
        std.debug.assert(entry.value_ptr.len == arr_size);
        try write_vtk_data(vtk_string, entry.key_ptr.*, entry.value_ptr.*);
    }
}

test "export array" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Define a new ArrayHashMap with keys of type []const u8 (strings) and values of type i32 (integers)
    var map = std.StringArrayHashMap([]const f32).init(allocator);
    defer map.deinit();

    const dims: [2]u32 = .{ 2, 4 };

    inline for (.{ "rho", "ux" }) |macr| {
        const my_arr: [8]f32 = .{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 };
        try map.put(macr, my_arr[0..my_arr.len]);
    }
    var data_wr = std.ArrayList(u8).init(allocator);

    try write_vtk(&data_wr, map, &dims);

    try utils.writeArrayListToFile("teste.vtk", data_wr.items);
}
