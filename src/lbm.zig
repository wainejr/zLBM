const std = @import("std");
const Allocator = std.mem.Allocator;

const VelSet = enum { D2Q9 };

const vel_set_use = VelSet.D2Q9;
const dim = switch (vel_set_use) {
    VelSet.D2Q9 => 2,
};
const n_pop = switch (vel_set_use) {
    VelSet.D2Q9 => 9,
};

const pop_dir: [n_pop][dim]i8 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ [_]i8{ 0, 0 }, [_]i8{ 1, 0 }, [_]i8{ 0, 1 }, [_]i8{ -1, 0 }, [_]i8{ 0, -1 }, [_]i8{ 1, 1 }, [_]i8{ -1, 1 }, [_]i8{ -1, -1 }, [_]i8{ 1, -1 } },
};

const pop_weights: [n_pop]f32 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ 4.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0 },
};
const cs2: f32 = 1.0 / 3.0;
const tau: f32 = 0.9;

const domain_size: [dim]u32 = .{ 32, 32 };
const array_size = domain_size[0] * domain_size[1] * (if (dim == 2) 1 else domain_size[2]);

fn idx2pos(idx: usize) [dim]u32 {
    if (dim == 2) {
        return .{ @intCast(idx % domain_size[0]), @intCast(idx / domain_size[0]) };
    } else {
        return .{ @intCast(idx % domain_size[0]), @intCast((idx / domain_size[0]) % domain_size[1]), @intCast(idx / (domain_size[0] * domain_size[1])) };
    }
}

fn pos2idx(pos: [dim]u32) usize {
    if (dim == 2) {
        return pos[0] + pos[1] * domain_size[0];
    } else {
        return pos[0] + domain_size[0] * (pos[1] + pos[2] * domain_size[1]);
    }
}

fn idxPop(pos: [dim]u32, i: u8) usize {
    return (pos2idx(pos)) * n_pop + i;
}

test "test Idx" {
    const assert = std.debug.assert;
    var count: usize = 0;
    for (0..array_size) |idx| {
        const pos = idx2pos(idx);
        const retIdx = pos2idx(pos);
        assert(retIdx == idx);
        for (0..dim) |d| {
            assert(pos[d] >= 0);
            assert(pos[d] < domain_size[d]);
        }
        for (0..n_pop) |i| {
            const popIdx = idxPop(pos, @intCast(i));
            assert(count == popIdx);
            count += 1;
        }
    }
}

fn dot_prod(comptime T: type, x: *const [dim]T, y: *const [dim]T) T {
    var sum: T = 0;
    for (x, y) |i, j| {
        sum += i * j;
    }
    return sum;
}

fn func_feq(rho: f32, u: [dim]f32, i: usize) f32 {
    // const ud = .{ u[0], u[1] };
    const popDir: [2]f32 = .{ @floatFromInt(pop_dir[i][0]), @floatFromInt(pop_dir[i][1]) };
    const uc: f32 = dot_prod(f32, &u, &popDir);
    const uu: f32 = dot_prod(f32, &u, &popDir);

    return rho * pop_weights[i] * (1 + uc / cs2 + (uc * uc) / (2 * cs2 * cs2) - (uu) / (2 * cs2));
}

test "func_eq const" {
    const assert = std.debug.assert;
    const rho: f32 = 1;
    const u: [dim]f32 = .{ 0, 0 };
    for (0..n_pop) |i| {
        const feq = func_feq(rho, u, i);
        assert(feq == pop_weights[i]);
    }
}

pub fn macroscopics(
    pop_arr: []f32,
    rho_arr: []f32,
    ux_arr: []f32,
    uy_arr: []f32,
) void {
    for (0..array_size) |idx| {
        const pos = idx2pos(idx);
        var pop: [n_pop]f32 = undefined;
        for (0..n_pop) |j| {
            pop[j] = pop_arr[idxPop(pos, @intCast(j))];
        }

        var rho: f32 = 0;
        for (pop) |p| {
            rho += p;
        }
        var u: [dim]f32 = .{0} ** dim;
        for (0..n_pop) |j| {
            for (0..dim) |d| {
                const fdir: f32 = @floatFromInt(pop_dir[j][d]);
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
    for (0..array_size) |idx| {
        const pos = idx2pos(idx);
        const rho = rho_arr[idx];
        const ux = ux_arr[idx];
        const uy = uy_arr[idx];
        const u: [dim]f32 = .{ ux, uy };
        var pop: [n_pop]f32 = undefined;
        for (0..n_pop) |j| {
            pop[j] = pop_arr[idxPop(pos, @intCast(j))];
        }
        inline for (0..n_pop) |i| {
            const feq = func_feq(rho, u, i);
            const f_coll = pop[i] + (pop[i] - feq) / tau;
            pop_arr[idxPop(pos, i)] = f_coll;
        }
    }
}

pub fn streaming(popA_arr: []f32, popB_arr: []f32) void {
    for (0..array_size) |idx| {
        const pos = idx2pos(idx);
        for (0..n_pop) |i| {
            // posTo = pos + pop_dir[i]
            const popDir: [dim]i32 = .{ @intCast(pop_dir[i][0]), @intCast(pop_dir[i][1]) };
            var posTo: [dim]i32 = .{ @intCast(pos[0]), @intCast(pos[1]) };
            inline for (0..dim) |d| {
                posTo[d] += popDir[d];
                if (posTo[d] < 0) {
                    posTo[d] += @intCast(domain_size[d]);
                } else if (posTo[d] >= domain_size[d]) {
                    posTo[d] -= @intCast(domain_size[d]);
                }
            }
            const posToU: [dim]u32 = .{ @intCast(posTo[0]), @intCast(posTo[1]) };

            popB_arr[idxPop(posToU, @intCast(i))] = popA_arr[idxPop(pos, @intCast(i))];
        }
    }
}

const LBMArrays = struct {
    popA: []f32,
    popB: []f32,
    ux: []f32,
    uy: []f32,
    rho: []f32,

    pub fn initialize(self: *const LBMArrays) void {
        for (0..array_size) |idx| {
            const pos = idx2pos(idx);

            self.ux[idx] = 0;
            self.uy[idx] = 0;
            self.rho[idx] = 1;

            inline for (0..n_pop) |j| {
                self.popA[idxPop(pos, j)] = pop_weights[j];
                self.popB[idxPop(pos, j)] = pop_weights[j];
            }
        }
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
    const popA: []f32 = try allocator.alloc(f32, array_size * n_pop);
    const popB: []f32 = try allocator.alloc(f32, array_size * n_pop);
    const rho: []f32 = try allocator.alloc(f32, array_size);
    const ux: []f32 = try allocator.alloc(f32, array_size);
    const uy: []f32 = try allocator.alloc(f32, array_size);

    return LBMArrays{
        .popA = popA,
        .popB = popB,
        .rho = rho,
        .ux = ux,
        .uy = uy,
    };
}
