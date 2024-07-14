const std = @import("std");
const vtk = @import("vtk.zig");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const Allocator = std.mem.Allocator;

fn dot_prod(comptime T: type, x: *const [defs.dim]T, y: *const [defs.dim]T) T {
    var sum: T = 0;
    for (x, y) |i, j| {
        sum += i * j;
    }
    return sum;
}

fn func_feq(rho: f32, u: [defs.dim]f32, i: usize) f32 {
    // const ud = .{ u[0], u[1] };
    const popDir: [2]f32 = .{ @floatFromInt(defs.pop_dir[i][0]), @floatFromInt(defs.pop_dir[i][1]) };
    const uc: f32 = dot_prod(f32, &u, &popDir);
    const uu: f32 = dot_prod(f32, &u, &u);

    return rho * defs.pop_weights[i] * (1 + uc / defs.cs2 + (uc * uc) / (2 * defs.cs2 * defs.cs2) - (uu) / (2 * defs.cs2));
}

test "func_eq const" {
    const assert = std.debug.assert;
    const rho: f32 = 1;
    const u: [defs.dim]f32 = .{ 0, 0 };
    for (0..defs.n_pop) |i| {
        const feq = func_feq(rho, u, i);
        assert(feq == defs.pop_weights[i]);
    }
}

pub fn macroscopics(
    pop_arr: []f32,
    rho_arr: []f32,
    ux_arr: []f32,
    uy_arr: []f32,
) void {
    for (0..defs.n_nodes) |idx| {
        const pos = fidx.idx2pos(idx);
        var pop: [defs.n_pop]f32 = undefined;
        for (0..defs.n_pop) |j| {
            pop[j] = pop_arr[fidx.idxPop(pos, @intCast(j))];
        }

        var rho: f32 = 0;
        for (pop) |p| {
            rho += p;
        }
        var u: [defs.dim]f32 = .{0} ** defs.dim;
        for (0..defs.n_pop) |j| {
            for (0..defs.dim) |d| {
                const fdir: f32 = @floatFromInt(defs.pop_dir[j][d]);
                u[d] += pop[j] * fdir / rho;
            }
        }

        rho_arr[idx] = rho;
        ux_arr[idx] = u[0];
        uy_arr[idx] = u[1];
    }
}

//  Open Security Training 2

pub fn collision(pop_arr: []f32, rho_arr: []f32, ux_arr: []f32, uy_arr: []f32) void {
    for (0..defs.n_nodes) |idx| {
        const pos = fidx.idx2pos(idx);
        const rho = rho_arr[idx];
        const ux = ux_arr[idx];
        const uy = uy_arr[idx];
        const u: [defs.dim]f32 = .{ ux, uy };
        var pop: [defs.n_pop]f32 = undefined;
        for (0..defs.n_pop) |j| {
            pop[j] = pop_arr[fidx.idxPop(pos, @intCast(j))];
        }
        inline for (0..defs.n_pop) |i| {
            const feq = func_feq(rho, u, i);
            const f_coll = pop[i] - (pop[i] - feq) / defs.tau;
            pop_arr[fidx.idxPop(pos, i)] = f_coll;
        }
    }
}

pub fn streaming(popA_arr: []f32, popB_arr: []f32) void {
    for (0..defs.n_nodes) |idx| {
        const pos = fidx.idx2pos(idx);
        for (0..defs.n_pop) |i| {
            // posTo = pos + defs.pop_dir[i]
            const popDir: [defs.dim]i32 = .{ @intCast(defs.pop_dir[i][0]), @intCast(defs.pop_dir[i][1]) };
            var posTo: [defs.dim]i32 = .{ @intCast(pos[0]), @intCast(pos[1]) };
            inline for (0..defs.dim) |d| {
                posTo[d] += popDir[d];
                if (posTo[d] < 0) {
                    posTo[d] += @intCast(defs.domain_size[d]);
                } else if (posTo[d] >= defs.domain_size[d]) {
                    posTo[d] -= @intCast(defs.domain_size[d]);
                }
            }
            const posToU: [defs.dim]u32 = .{ @intCast(posTo[0]), @intCast(posTo[1]) };
            // std.debug.print("pop {} pos to {} {} pos {} {} dir {} {}\n", .{ i, posToU[0], posToU[1], pos[0], pos[1], popDir[0], popDir[1] });

            popB_arr[fidx.idxPop(posToU, @intCast(i))] = popA_arr[fidx.idxPop(pos, @intCast(i))];
        }
    }
    std.debug.print("\n", .{});
}

const LBMArrays = struct {
    popA: []f32,
    popB: []f32,
    ux: []f32,
    uy: []f32,
    rho: []f32,

    pub fn initialize(self: *const LBMArrays) void {
        for (0..defs.n_nodes) |idx| {
            const pos = fidx.idx2pos(idx);
            std.debug.print("pos {} {}\n", .{ pos[0], pos[1] });

            self.rho[idx] = 1;
            const posF: [defs.dim]f32 = .{ @floatFromInt(pos[0]), @floatFromInt(pos[1]) };
            const posNorm: [defs.dim]f32 = .{ posF[0] / defs.domain_size[0], posF[1] / defs.domain_size[1] };
            const velNorm = 0.01;
            const ux = velNorm * std.math.sin(posNorm[0] * 2 * std.math.pi) * std.math.cos(posNorm[1] * 2 * std.math.pi);
            const uy = -velNorm * std.math.cos(posNorm[0] * 2 * std.math.pi) * std.math.sin(posNorm[1] * 2 * std.math.pi);
            self.ux[idx] = ux;
            self.uy[idx] = uy;
            self.ux[idx] = 0.01 * ((((defs.domain_size[1] - 1) - posF[1]) * posF[1]) / (defs.domain_size[1] - 1));
            self.uy[idx] = 0;

            const u: [defs.dim]f32 = .{ self.ux[idx], self.uy[idx] };
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

        inline for (.{ "rho", "ux", "uy" }) |macr_name| {
            try map.put(macr_name, @field(self, macr_name));
        }

        const filename_use = try std.fmt.bufPrint(buff_slice, "output/macrs{d:0>5}.vtk", .{time_step});
        try vtk.write_vtk(&data_wr, map, &defs.domain_size);
        try utils.writeArrayListToFile(filename_use, &data_wr);
    }
};

pub fn run_time_step(lbm_arr: LBMArrays, time_step: u32) void {
    const popMain_arr = if (time_step % 2 == 0) lbm_arr.popA else lbm_arr.popB;
    const popAux_arr = if (time_step % 2 == 1) lbm_arr.popA else lbm_arr.popB;

    macroscopics(popMain_arr, lbm_arr.rho, lbm_arr.ux, lbm_arr.uy);
    collision(popMain_arr, lbm_arr.rho, lbm_arr.ux, lbm_arr.uy);
    streaming(popMain_arr, popAux_arr);
}

pub fn allocate_arrs(allocator: *const Allocator) !LBMArrays {
    const popA: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const popB: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const rho: []f32 = try allocator.alloc(f32, defs.n_nodes);
    const ux: []f32 = try allocator.alloc(f32, defs.n_nodes);
    const uy: []f32 = try allocator.alloc(f32, defs.n_nodes);

    return LBMArrays{
        .popA = popA,
        .popB = popB,
        .rho = rho,
        .ux = ux,
        .uy = uy,
    };
}
