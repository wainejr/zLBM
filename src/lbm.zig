const VelSet = enum { D2Q9 };

const vel_set_use = VelSet.D2Q9;
const dim = switch (vel_set_use) {
    VelSet.D2Q9 => 2,
};
const n_pop = switch (vel_set_use) {
    VelSet.D2Q9 => 9,
};

const pop_dir: [n_pop][dim]u8 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ [_]u8{ 0, 0 }, [_]u8{ 1, 0 }, [_]u8{ 0, 1 }, [_]u8{ -1, 0 }, [_]u8{ 0, -1 }, [_]u8{ 1, 1 }, [_]u8{ -1, 1 }, [_]u8{ -1, -1 }, [_]u8{ 1, -1 } },
};

const pop_weights: [n_pop]f32 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ 4.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0 },
};
const cs2: f32 = 1.0 / 3.0;

fn dot_prod(x: []f32, y: []f32) f32 {
    var sum: f32 = 0;
    for (x, y) |i, j| {
        sum += i * j;
    }
    return sum;
}

fn feq(rho: f32, u: [dim]f32, comptime i: usize) f32 {
    const uc = dot_prod(u, pop_dir[i]);
    const uu = dot_prod(u, pop_dir[i]);

    return rho * pop_weights[i] * (1 + uc / cs2 + (uc * uc) / (2 * cs2 * cs2) - (uu) / (2 * cs2));
}

pub fn macroscopics(
    pop_arr: [][n_pop]f32,
    rho_arr: []f32,
    u_arr: [][dim]f32,
) void {
    var i: usize = 0;
    while (i < pop_arr.len) : (i += 1) {
        const pop = pop_arr[i];
        var rho: f32 = 0;
        for (pop) |p| {
            rho += p;
        }
        var u: [dim]f32 = .{0} ** dim;
        for (pop, 0..) |p, j| {
            for (dim) |d| {
                u[d] += p * pop_dir[j];
            }
        }
        rho_arr[i] = rho;
        u_arr[i] = u;
    }
}

pub fn collision() void {}

pub fn streaming() void {}
