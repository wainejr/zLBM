const std = @import("std");
const lbm = @import("lbm.zig");
const vtk = @import("vtk.zig");
const defs = @import("defines.zig");
const tracy = @import("tracy");

pub fn main() !void {
    tracy.setThreadName("Other");
    defer tracy.message("Graceful other thread exit");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const lbm_arrays = try lbm.allocate_arrs(&allocator);
    lbm_arrays.initialize();

    // try lbm_arrays.export_arrays(allocator, 0);
    var timer = try std.time.Timer.start();

    const zone = tracy.initZone(@src(), .{ .name = "Simulation" });
    for (1..(defs.n_steps + 1)) |time_step| {
        lbm.run_time_step(lbm_arrays, @intCast(time_step));
        if (time_step % defs.freq_export == 0) {
            try lbm_arrays.export_arrays(allocator, @intCast(time_step));
            std.debug.print("Exported arrays in time step {}\n", .{time_step});
        }
    }
    zone.deinit();

    const time_passed_nano: f32 = @floatFromInt(timer.lap());
    const time_passed_sec: f32 = time_passed_nano / 1e9;

    const mlups: f32 = (defs.n_nodes * defs.n_steps) / (time_passed_sec * 1e6);

    std.debug.print("Finished simulation!\n", .{});
    std.debug.print("MLUPS {d:0.2}\n", .{mlups});
    std.debug.print("Time elapsed {d:0.2}s\n", .{time_passed_sec});
}
