const std = @import("std");
const vtk = @import("vtk.zig");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const Allocator = std.mem.Allocator;

inline fn dot_prod(comptime T: type, x: *const [defs.dim]T, y: *const [defs.dim]T) T {
    var sum: T = 0;
    for (x, y) |i, j| {
        sum += i * j;
    }
    return sum;
}

inline fn func_feq(rho: f32, u: [defs.dim]f32, i: usize) f32 {
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
    for (0..defs.n_pop) |i| {
        const feq = func_feq(rho, u, i);
        assert(feq == defs.pop_weights[i]);
    }
}

pub fn macroscopics(idx: usize, pop: *[defs.n_pop]f32, rho: *f32, u: *[defs.dim]f32) void {
    _ = idx;
    rho.* = 0;
    inline for (pop) |p| {
        rho.* += p;
    }
    u.* = .{0} ** defs.dim;
    inline for (0..defs.n_pop) |j| {
        inline for (0..defs.dim) |d| {
            const fdir: f32 = @floatFromInt(defs.pop_dir[j][d]);
            u.*[d] += pop[j] * fdir / rho.*;
        }
    }
}

//  Open Security Training 2

pub fn collision(idx: usize, pop: *[defs.n_pop]f32, rho: f32, u: [defs.dim]f32) void {
    _ = idx;

    inline for (0..defs.n_pop) |i| {
        const feq = func_feq(rho, u, i);
        const f_coll = pop[i] - (pop[i] - feq) / defs.tau;
        pop[i] = f_coll;
    }
}

pub fn streaming(idx: usize, pop: *[defs.n_pop]f32, popStream_arr: []f32) void {
    const pos = fidx.idx2pos(idx);
    for (0..defs.n_pop) |i| {
        // posTo = pos + defs.pop_dir[i]
        var popDir: [defs.dim]i32 = undefined;
        inline for (0..defs.dim) |d| {
            popDir[d] = @intCast(defs.pop_dir[i][d]);
        }
        var posTo: [defs.dim]i32 = undefined;
        inline for (0..defs.dim) |d| {
            posTo[d] = @intCast(pos[d]);
            posTo[d] += popDir[d];
            if (posTo[d] < 0) {
                posTo[d] += @intCast(defs.domain_size[d]);
            } else if (posTo[d] >= defs.domain_size[d]) {
                posTo[d] -= @intCast(defs.domain_size[d]);
            }
        }
        var posToU: [defs.dim]u32 = undefined;
        inline for (0..defs.dim) |d| {
            posToU[d] = @intCast(posTo[d]);
        }
        // std.debug.print("pop {} pos to {} {} pos {} {} dir {} {}\n", .{ i, posToU[0], posToU[1], pos[0], pos[1], popDir[0], popDir[1] });

        popStream_arr[fidx.idxPop(pos, @intCast(i))] = pop[i];
    }
}

const LBMArrays = struct {
    popA: []f32,
    popB: []f32,
    u: [defs.dim][]f32,
    rho: []f32,

    pub fn initialize(self: *const LBMArrays) void {
        for (0..defs.n_nodes) |idx| {
            const pos = fidx.idx2pos(idx);
            // std.debug.print("pos {} {}\n", .{ pos[0], pos[1] });s

            self.rho[idx] = 1;
            var posF: [defs.dim]f32 = undefined;
            var posNorm: [defs.dim]f32 = undefined;
            inline for (0..defs.dim) |d| {
                posF[d] = @floatFromInt(pos[d]);
                posNorm[d] = posF[d] / defs.domain_size[d];
            }

            const velNorm = 0.01;
            // const ux = velNorm * std.math.sin(posNorm[0] * 2 * std.math.pi) * std.math.cos(posNorm[1] * 2 * std.math.pi);
            // const uy = -velNorm * std.math.cos(posNorm[0] * 2 * std.math.pi) * std.math.sin(posNorm[1] * 2 * std.math.pi);

            self.u[0][idx] = velNorm * ((((defs.domain_size[1] - 1) - posF[1]) * posF[1]) / (defs.domain_size[1] - 1));
            self.u[1][idx] = 0;
            if (defs.dim == 3) {
                self.u[2][idx] = 0;
            }

            var u: [defs.dim]f32 = undefined;
            inline for (0..defs.dim) |d| {
                u[d] = self.u[d][idx];
            }

            inline for (0..defs.n_pop) |j| {
                self.popA[fidx.idxPop(pos, j)] = func_feq(self.rho[idx], u, j);
                self.popB[fidx.idxPop(pos, j)] = func_feq(self.rho[idx], u, j);
            }
        }
    }

    pub fn export_arrays(self: *const LBMArrays, allocator: std.mem.Allocator, time_step: u32) !void {
        var buff: [50]u8 = undefined;
        const buff_slice = buff[0..];

        var map = std.StringArrayHashMap([]const f32).init(allocator);
        defer map.deinit();
        var data_wr = std.ArrayList(u8).init(allocator);
        defer data_wr.deinit();

        try map.put("rho", @field(self, "rho"));
        const u_names: [defs.dim][]const u8 = if (defs.dim == 2) .{ "ux", "uy" } else .{ "ux", "uy", "uz" };
        inline for (0..defs.dim, u_names) |d, macr_name| {
            try map.put(macr_name, self.u[d]);
        }

        const filename_use = try std.fmt.bufPrint(buff_slice, "output/macrs{d:0>5}.vtk", .{time_step});
        try vtk.write_vtk(&data_wr, map, &defs.domain_size);
        try utils.writeArrayListToFile(filename_use, &data_wr);
    }
};

pub fn run_time_step(lbm_arr: LBMArrays, time_step: u32) void {
    const popMain_arr = if (time_step % 2 == 0) lbm_arr.popA else lbm_arr.popB;
    const popAux_arr = if (time_step % 2 == 1) lbm_arr.popA else lbm_arr.popB;
    _ = popAux_arr;

    for (0..defs.n_nodes) |idx| {
        var pop: [defs.n_pop]f32 = undefined;
        const pos = fidx.idx2pos(idx);
        inline for (0..defs.n_pop) |j| {
            pop[j] = popMain_arr[fidx.idxPop(pos, @intCast(j))];
        }
        var rho: f32 = 0;
        var u: [defs.dim]f32 = .{0} ** defs.dim;
        macroscopics(idx, &pop, &rho, &u);
        // const rho = lbm_arr.rho[idx];
        // var u: [defs.dim]f32 = undefined;
        // inline for (0..defs.dim) |d| {
        //     u[d] = lbm_arr.u[d][idx];
        // }
        collision(idx, &pop, rho, u);
        streaming(idx, &pop, popMain_arr);
    }
}

pub fn allocate_arrs(allocator: *const Allocator) !LBMArrays {
    const popA: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const popB: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const rho: []f32 = try allocator.alloc(f32, defs.n_nodes);
    var u: [defs.dim][]f32 = undefined;
    inline for (0..defs.dim) |d| {
        u[d] = try allocator.alloc(f32, defs.n_nodes);
    }

    return LBMArrays{ .popA = popA, .popB = popB, .rho = rho, .u = u };
}
