const std = @import("std");
const vtk = @import("vtk.zig");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const ibm = @import("ibm.zig");
const cl = @import("cl.zig");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cDefine("CL_TARGET_OPENCL_VERSION", "110");
    @cInclude("CL/cl.h");
});

inline fn dot_prod(comptime T: type, x: *const [defs.dim]T, y: *const [defs.dim]T) T {
    var sum: T = 0;
    for (x, y) |i, j| {
        sum += i * j;
    }
    return sum;
}

inline fn func_feq(rho: f32, u: [defs.dim]f32, comptime i: usize) f32 {
    // const ud = .{ u[0], u[1] };
    var popDir: [defs.dim]f32 = undefined;
    inline for (0..defs.dim) |d| {
        popDir[d] = @floatFromInt(defs.pop_dir[i][d]);
    }
    const uc: f32 = dot_prod(f32, &u, &popDir);
    const uu: f32 = dot_prod(f32, &u, &u);

    return rho * defs.pop_weights[i] * (1 + uc / defs.cs2 + (uc * uc) / (2 * defs.cs2 * defs.cs2) - (uu) / (2 * defs.cs2));
}

test "func_eq const" {
    const assert = std.debug.assert;
    const rho: f32 = 1;
    const u: [defs.dim]f32 = .{0} ** defs.dim;
    inline for (0..defs.n_pop) |i| {
        const feq = func_feq(rho, u, i);
        assert(feq == defs.pop_weights[i]);
    }
}

pub const LBMArrays = struct {
    const Self = @This();

    popA: cl.CLBuffer(f32),
    popB: cl.CLBuffer(f32),
    u: [defs.dim]cl.CLBuffer(f32),
    rho: cl.CLBuffer(f32),
    force_ibm: [defs.dim]cl.CLBuffer(f32),

    pub fn allocate(ctx: c.cl_context, allocator: Allocator) !Self {
        var popA = try cl.CLBuffer(f32).init(defs.n_nodes * defs.n_pop, ctx);
        try popA.allocate_host(allocator);

        var popB = try cl.CLBuffer(f32).init(defs.n_nodes * defs.n_pop, ctx);
        try popB.allocate_host(allocator);

        var rho = try cl.CLBuffer(f32).init(defs.n_nodes, ctx);
        try rho.allocate_host(allocator);

        var u: [defs.dim]cl.CLBuffer(f32) = undefined;
        var force_ibm: [defs.dim]cl.CLBuffer(f32) = undefined;

        inline for (0..defs.dim) |d| {
            u[d] = try cl.CLBuffer(f32).init(defs.n_nodes, ctx);
            try u[d].allocate_host(allocator);
            force_ibm[d] = try cl.CLBuffer(f32).init(defs.n_nodes, ctx);
            try force_ibm[d].allocate_host(allocator);
        }

        return LBMArrays{ .popA = popA, .popB = popB, .rho = rho, .u = u, .force_ibm = force_ibm };
    }

    pub fn free(self: Self) void {
        self.popA.free();
        self.popB.free();
        self.rho.free();
        for (0..defs.dim) |d| {
            self.u[d].free();
            self.force_ibm[d].free();
        }
    }

    pub fn sync_host2device(self: *const Self, queue: cl.CLQueue) !void {
        try self.popA.host2device(queue);
        try self.popB.host2device(queue);
        try self.rho.host2device(queue);
        for (0..defs.dim) |d| {
            try self.u[d].host2device(queue);
            try self.force_ibm[d].host2device(queue);
        }
    }

    pub fn sync_device2host(self: *const Self, queue: cl.CLQueue) !void {
        try self.popA.device2host(queue);
        try self.popB.device2host(queue);
        try self.rho.device2host(queue);
        for (0..defs.dim) |d| {
            try self.u[d].device2host(queue);
            try self.force_ibm[d].device2host(queue);
        }
    }

    pub fn initialize(self: *const Self, queue: cl.CLQueue) !void {
        for (0..defs.n_nodes) |idx| {
            const pos = fidx.idx2pos(idx);
            // std.debug.print("pos {} {}\n", .{ pos[0], pos[1] });

            self.rho.h_buff.?.items[idx] = 1;
            var posF: [defs.dim]f32 = undefined;
            var posNorm: [defs.dim]f32 = undefined;
            inline for (0..defs.dim) |d| {
                posF[d] = @floatFromInt(pos[d]);
                posNorm[d] = posF[d] / defs.domain_size[d];
            }

            const velNorm = 0.01;
            // const ux = velNorm * std.math.sin(posNorm[0] * 2 * std.math.pi) * std.math.cos(posNorm[1] * 2 * std.math.pi);
            // const uy = -velNorm * std.math.cos(posNorm[0] * 2 * std.math.pi) * std.math.sin(posNorm[1] * 2 * std.math.pi);

            self.u[0].h_buff.?.items[idx] = velNorm * ((1 - posNorm[1]) * posNorm[1]);
            self.u[1].h_buff.?.items[idx] = 0;
            if (defs.dim == 3) {
                self.u[2].h_buff.?.items[idx] = 0;
            }

            var u: [defs.dim]f32 = undefined;
            inline for (0..defs.dim) |d| {
                u[d] = self.u[d].h_buff.?.items[idx];
                self.force_ibm[d].h_buff.?.items[idx] = 0;
            }

            inline for (0..defs.n_pop) |j| {
                self.popA.h_buff.?.items[fidx.idxPop(pos, j)] = func_feq(self.rho.h_buff.?.items[idx], u, j);
                self.popB.h_buff.?.items[fidx.idxPop(pos, j)] = func_feq(self.rho.h_buff.?.items[idx], u, j);
            }
        }
        try self.sync_host2device(queue);
    }

    pub fn export_arrays(self: *const Self, allocator: std.mem.Allocator, queue: cl.CLQueue, time_step: u32) !void {
        try self.sync_device2host(queue);

        var buff: [50]u8 = undefined;
        const buff_slice = buff[0..];

        var map = std.StringArrayHashMap([]const f32).init(allocator);
        defer map.deinit();
        var data_wr = std.ArrayList(u8).init(allocator);
        defer data_wr.deinit();

        try map.put("rho", @field(self, "rho").h_buff.?.items);
        const u_names: [defs.dim][]const u8 = if (defs.dim == 2) .{ "ux", "uy" } else .{ "ux", "uy", "uz" };
        inline for (0..defs.dim, u_names) |d, macr_name| {
            try map.put(macr_name, self.u[d].h_buff.?.items);
        }
        const f_names: [defs.dim][]const u8 = if (defs.dim == 2) .{ "force_IBMx", "force_IBMy" } else .{ "force_IBMx", "force_IBMy", "force_IBMz" };
        inline for (0..defs.dim, f_names) |d, macr_name| {
            try map.put(macr_name, self.force_ibm[d].h_buff.?.items);
        }

        const filename_use = try std.fmt.bufPrint(buff_slice, "output/macrs{d:0>5}.vtk", .{time_step});
        try vtk.write_vtk(&data_wr, map, &defs.domain_size);
        try utils.writeArrayListToFile(filename_use, data_wr.items);
    }
};

pub fn run_IBM_iteration(bodies: []const ibm.BodyIBM, lbm_arr: LBMArrays, time_step: u32) void {
    _ = time_step;
    if (bodies.len == 0) {
        return;
    }
    _ = lbm_arr;

    // for (bodies) |b| {
    //     b.run_ibm(lbm_arr.rho, lbm_arr.u, lbm_arr.force_ibm);
    // }
}

pub fn run_time_step(lbm_arr: LBMArrays, time_step: u32) void {
    const popMain_arr = if (time_step % 2 == 0) lbm_arr.popA else lbm_arr.popB;
    const popAux_arr = if (time_step % 2 == 1) lbm_arr.popA else lbm_arr.popB;
    _ = popMain_arr;
    _ = popAux_arr;
}

test "memory allocation OpenCL" {
    const device = try cl.cl_get_device();
    const allocator = std.testing.allocator;

    const ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return cl.CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const queue = try cl.CLQueue.init(ctx, device);
    defer queue.free();

    const lbm_array = try LBMArrays.allocate(ctx, allocator);
    defer lbm_array.free();

    try lbm_array.initialize(queue);
    try lbm_array.export_arrays(allocator, queue, 0);
}
