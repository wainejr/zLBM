const std = @import("std");
const lbm = @import("lbm.zig");
const ibm = @import("ibm.zig");
const vtk = @import("vtk.zig");
const defs = @import("defines.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const lbm_arrays = try lbm.LBMArrays.allocate(null, &allocator);
    lbm_arrays.initialize();
    // const body_ibm = try ibm.BodyIBM.create_basic_body(allocator);
    // try body_ibm.export_csv(allocator, "output/body_pos_0.csv");
    const bodies: [0]ibm.BodyIBM = .{};

    try lbm_arrays.export_arrays(allocator, 0);
    var timer = try std.time.Timer.start();

    for (1..(defs.n_steps + 1)) |time_step| {
        lbm.run_time_step(lbm_arrays, @intCast(time_step));
        // for (0..defs.ibm_n_iterations) |_| {
        for (0..1) |_| { // Use 1 iteration to not update macrs
            lbm.run_IBM_iteration(bodies[0..], lbm_arrays, @intCast(time_step));
        }
        if (time_step % defs.freq_export == 0) {
            try lbm_arrays.export_arrays(allocator, @intCast(time_step));

            for (bodies) |b| {
                var buffer: [100]u8 = undefined;
                const buffer_slice = buffer[0..];
                const body_path = try std.fmt.bufPrint(buffer_slice, "output/body_pos_{}.csv", .{time_step});
                try b.export_csv(allocator, body_path);
            }

            std.debug.print("Exported arrays in time step {}\n", .{time_step});
        }
    }

    const time_passed_nano: f64 = @floatFromInt(timer.lap());
    const time_passed_sec: f64 = time_passed_nano / 1e9;

    const mlups: f64 = (@as(usize, @intCast(defs.n_nodes)) * defs.n_steps) / (time_passed_sec * 1e6);

    std.debug.print("Finished simulation!\n", .{});
    std.debug.print("MLUPS {d:0.2}\n", .{mlups});
    std.debug.print("Time elapsed {d:0.2}s\n", .{time_passed_sec});
}
