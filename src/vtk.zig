const std = @import("std");
const lbm = @import("lbm.zig");

// const string header =
//             "# vtk DataFile Version 3.0\nData\nBINARY\nDATASET STRUCTURED_POINTS\n"
//             "DIMENSIONS "+to_string(Nx)+" "+to_string(Ny)+" "+to_string(Nz)+"\n"
//             "ORIGIN "+to_string(origin.x)+" "+to_string(origin.y)+" "+to_string(origin.z)+"\n"
//             "SPACING "+to_string(spacing)+" "+to_string(spacing)+" "+to_string(spacing)+"\n"
//             "POINT_DATA "+to_string((ulong)Nx*(ulong)Ny*(ulong)Nz)+"\nSCALARS data "+vtk_type()+" "+to_string(dimensions())+"\nLOOKUP_TABLE default\n"
//         ;
//         T* data = new T[range()];
//         parallel_for(length(), [&](ulong i) {
//             for(uint d=0u; d<dimensions(); d++) {
//                 data[i*(ulong)dimensions()+(ulong)d] = reverse_bytes((T)(unit_conversion_factor*reference(i, d))); // SoA <- AoS
//             }
//         });

// Function to append formatted strings to the list
fn appendFormatted(list: *std.ArrayList(u8), comptime format_string: []const u8, args: anytype) !void {
    var buffer: [100]u8 = undefined;
    const buffer_slice = buffer[0..];

    const str_add = try std.fmt.bufPrint(buffer_slice, format_string, args);

    try list.appendSlice(str_add);
}

pub fn export_array(vtk_string: *std.ArrayList(u8), arr: []const f32, dims: []const u32) !void {
    const dims_use: [3]u32 = .{ dims[0], dims[1], if (dims.len < 3) 1 else dims[2] };

    try vtk_string.appendSlice("# vtk DataFile Version 3.0\nData\nBINARY\nDATASET STRUCTURED_POINTS\n");

    // "DIMENSIONS "+to_string(Nx)+" "+to_string(Ny)+" "+to_string(Nz)+"\n"
    try vtk_string.appendSlice("DIMENSIONS ");
    for (dims_use) |d| {
        try appendFormatted(vtk_string, "{} ", .{d});
    }
    try vtk_string.appendSlice("\n");
    // "ORIGIN "+to_string(origin.x)+" "+to_string(origin.y)+" "+to_string(origin.z)+"\n"
    try vtk_string.appendSlice("ORIGIN ");
    for (dims_use) |_| {
        try appendFormatted(vtk_string, "{} ", .{0});
    }
    try vtk_string.appendSlice("\n");
    // "SPACING "+to_string(spacing)+" "+to_string(spacing)+" "+to_string(spacing)+"\n"
    try vtk_string.appendSlice("SPACING ");
    for (dims_use) |_| {
        try appendFormatted(vtk_string, "{} ", .{1});
    }
    try vtk_string.appendSlice("\n");
    // "POINT_DATA "+to_string((ulong)Nx*(ulong)Ny*(ulong)Nz)+
    try appendFormatted(vtk_string, "POINT_DATA {}\n", .{dims_use[0] * dims_use[1] * dims_use[2]});
    // "\nSCALARS data "+vtk_type()+" "+to_string(dimensions())+"\nLOOKUP_TABLE default\n"
    try vtk_string.appendSlice("SCALARS data float 1\n");
    try vtk_string.appendSlice("LOOKUP_TABLE default\n");

    // Write the scalar data in big-endian format
    var be_scalar: [4]u8 = undefined;
    for (arr) |value| {
        be_scalar = @bitCast(value);
        // std.debug.print("value {} bits {b:0>32} rev {b:0>32} scalars {x:} {x:} {x:} {x:}\n", .{ value, be_value, be_rev, be_scalar[0], be_scalar[1], be_scalar[2], be_scalar[3] });
        const be_use: [4]u8 = .{ be_scalar[3], be_scalar[2], be_scalar[1], be_scalar[0] };
        try vtk_string.appendSlice(be_use[0..4]);
    }
}
