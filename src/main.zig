const std = @import("std");
const lbm = @import("lbm.zig");
const vtk = @import("vtk.zig");
const defs = @import("defines.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const lbm_arrays = try lbm.allocate_arrs(&allocator);
    lbm_arrays.initialize();

    try lbm_arrays.export_arrays(allocator, 0);

    for (1..(defs.n_steps + 1)) |time_step| {
        std.debug.print("Running time step {}...\n", .{time_step});
        std.debug.print("rho {} ux {} uy {}...\n", .{ lbm_arrays.rho[0], lbm_arrays.u[0][0], lbm_arrays.u[1][0] });
        lbm.run_time_step(lbm_arrays, @intCast(time_step));
        if (time_step % defs.freq_export == 0) {
            try lbm_arrays.export_arrays(allocator, @intCast(time_step));
            std.debug.print("Exported arrays in time step {}\n", .{time_step});
        }
    }
    std.debug.print("Finished simulation!", .{});

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
