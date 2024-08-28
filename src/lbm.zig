const std = @import("std");
const vtk = @import("vtk.zig");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const ibm = @import("ibm.zig");
const Allocator = std.mem.Allocator;

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

inline fn source_term(u: [defs.dim]f32, force: [defs.dim]f32, comptime i: usize) f32 {
    // const ud = .{ u[0], u[1] };
    var popDir: [defs.dim]f32 = undefined;
    inline for (0..defs.dim) |d| {
        popDir[d] = @floatFromInt(defs.pop_dir[i][d]);
    }
    var si: f32 = 0;
    const mul_term = (1 - 2 / defs.tau) * defs.pop_weights[i];
    inline for (0..defs.dim) |alfa| {
        const cia = popDir[alfa];
        si += mul_term * cia / defs.cs2 * force[alfa];
        inline for (0..defs.dim) |beta| {
            const cib = popDir[beta];
            const ciab = cia * cib;
            const k_dirac: f32 = if (alfa == beta) 1 else 0;
            si += mul_term * force[alfa] * (u[beta] * (ciab - defs.cs2 * k_dirac) / (defs.cs2 * defs.cs2));
        }
    }
    return si;
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

pub fn macroscopics(idx: usize, pop: *[defs.n_pop]f32, rho: *f32, u: *[defs.dim]f32, force: *[defs.dim]f32) void {
    _ = idx;
    rho.* = 0;
    inline for (pop) |p| {
        rho.* += p;
    }
    u.* = .{0} ** defs.dim;
    inline for (0..defs.n_pop) |j| {
        inline for (0..defs.dim) |d| {
            if (defs.pop_dir[j][d] == 0) {
                continue;
            }
            const fdir: f32 = @floatFromInt(defs.pop_dir[j][d]);
            u.*[d] += pop[j] * fdir;
        }
    }
    inline for (0..defs.dim) |d| {
        u.*[d] += force.*[d] / 2;
    }

    inline for (0..defs.dim) |d| {
        u.*[d] /= rho.*;
    }
}

//  Open Security Training 2

pub fn collision(idx: usize, pop: *[defs.n_pop]f32, rho: f32, u: [defs.dim]f32, force: [defs.dim]f32) void {
    _ = idx;

    inline for (0..defs.n_pop) |i| {
        const feq = func_feq(rho, u, i);
        const si = source_term(u, force, i);
        const f_coll = pop[i] - (pop[i] - feq) / defs.tau - si;
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
            posTo[d] += popDir[d] + defs.domain_size[d];
            posTo[d] = @mod(posTo[d], defs.domain_size[d]);
        }
        var posToU: [defs.dim]u32 = undefined;
        inline for (0..defs.dim) |d| {
            posToU[d] = @intCast(posTo[d]);
        }
        // std.debug.print("pop {} pos to {} {} pos {} {} dir {} {}\n", .{ i, posToU[0], posToU[1], pos[0], pos[1], popDir[0], popDir[1] });

        popStream_arr[fidx.idxPop(posToU, @intCast(i))] = pop[i];
    }
}

const LBMArrays = struct {
    const Self = @This();

    popA: []f32,
    popB: []f32,
    u: [defs.dim][]f32,
    rho: []f32,
    force_ibm: [defs.dim][]f32,

    pub fn initialize(self: *const Self) void {
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

            self.u[0][idx] = velNorm * ((1 - posNorm[1]) * posNorm[1]);
            self.u[1][idx] = 0;
            if (defs.dim == 3) {
                self.u[2][idx] = 0;
            }

            var u: [defs.dim]f32 = undefined;
            inline for (0..defs.dim) |d| {
                u[d] = self.u[d][idx];
                self.force_ibm[d][idx] = 0;
            }

            inline for (0..defs.n_pop) |j| {
                self.popA[fidx.idxPop(pos, j)] = func_feq(self.rho[idx], u, j);
                self.popB[fidx.idxPop(pos, j)] = func_feq(self.rho[idx], u, j);
            }
        }
    }

    pub fn update_macroscopics(self: Self, pop_arr: []f32) void {
        for (0..defs.n_nodes) |idx| {
            var pop: [defs.n_pop]f32 = undefined;
            const pos = fidx.idx2pos(idx);
            inline for (0..defs.n_pop) |j| {
                pop[j] = pop_arr[fidx.idxPop(pos, @intCast(j))];
            }
            var rho: f32 = 0;
            var u: [defs.dim]f32 = .{0} ** defs.dim;
            var force: [defs.dim]f32 = .{0} ** defs.dim;
            inline for (0..defs.dim) |d| {
                force[d] += defs.global_force[d];
                force[d] += self.force_ibm[d][idx];
            }
            macroscopics(idx, &pop, &rho, &u, &force);
            self.rho[idx] = rho;
            inline for (0..defs.dim) |d| {
                self.u[d][idx] = u[d];
            }
        }
    }

    pub fn export_arrays(self: *const Self, allocator: std.mem.Allocator, time_step: u32) !void {
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
        const f_names: [defs.dim][]const u8 = if (defs.dim == 2) .{ "force_IBMx", "force_IBMy" } else .{ "force_IBMx", "force_IBMy", "force_IBMz" };
        inline for (0..defs.dim, f_names) |d, macr_name| {
            try map.put(macr_name, self.force_ibm[d]);
        }

        const filename_use = try std.fmt.bufPrint(buff_slice, "output/macrs{d:0>5}.vtk", .{time_step});
        try vtk.write_vtk(&data_wr, map, &defs.domain_size);
        try utils.writeArrayListToFile(filename_use, data_wr.items);
    }
};

pub fn run_IBM_iteration(bodies: []const ibm.BodyIBM, lbm_arr: LBMArrays, time_step: u32) void {
    const popMain_arr = if (time_step % 2 == 0) lbm_arr.popA else lbm_arr.popB;
    lbm_arr.update_macroscopics(popMain_arr);
    for (bodies) |b| {
        b.run_ibm(lbm_arr.rho, lbm_arr.u, lbm_arr.force_ibm);
    }
    lbm_arr.update_macroscopics(popMain_arr);
}

pub fn reset_forces(lbm_arr: LBMArrays) void {
    for (0..defs.n_nodes) |idx| {
        inline for (0..defs.dim) |d| {
            lbm_arr.force_ibm[d][idx] = 0;
        }
    }
}

pub fn run_time_step(lbm_arr: LBMArrays, time_step: u32) void {
    const popMain_arr = if (time_step % 2 == 0) lbm_arr.popA else lbm_arr.popB;
    const popAux_arr = if (time_step % 2 == 1) lbm_arr.popA else lbm_arr.popB;

    for (0..defs.n_nodes) |idx| {
        var pop: [defs.n_pop]f32 = undefined;
        const pos = fidx.idx2pos(idx);
        inline for (0..defs.n_pop) |j| {
            pop[j] = popMain_arr[fidx.idxPop(pos, @intCast(j))];
        }
        var rho: f32 = 0;
        var u: [defs.dim]f32 = .{0} ** defs.dim;
        var force: [defs.dim]f32 = .{0} ** defs.dim;
        inline for (0..defs.dim) |d| {
            force[d] += defs.global_force[d];
            force[d] += lbm_arr.force_ibm[d][idx];
        }
        macroscopics(idx, &pop, &rho, &u, &force);

        lbm_arr.rho[idx] = rho;
        inline for (0..defs.dim) |d| {
            lbm_arr.u[d][idx] = u[d];
        }

        collision(idx, &pop, rho, u, force);
        streaming(idx, &pop, popAux_arr);
    }
}

pub fn allocate_arrs(allocator: *const Allocator) !LBMArrays {
    const popA: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const popB: []f32 = try allocator.alloc(f32, defs.n_nodes * defs.n_pop);
    const rho: []f32 = try allocator.alloc(f32, defs.n_nodes);
    var u: [defs.dim][]f32 = undefined;
    var force_ibm: [defs.dim][]f32 = undefined;
    inline for (0..defs.dim) |d| {
        u[d] = try allocator.alloc(f32, defs.n_nodes);
        force_ibm[d] = try allocator.alloc(f32, defs.n_nodes);
    }

    return LBMArrays{ .popA = popA, .popB = popB, .rho = rho, .u = u, .force_ibm = force_ibm };
}
