const utils = @import("utils.zig");

pub const cs2: f32 = 1.0 / 3.0;
pub const VelSet = enum { D2Q9 };
pub const dim = switch (vel_set_use) {
    VelSet.D2Q9 => 2,
};
pub const n_pop = switch (vel_set_use) {
    VelSet.D2Q9 => 9,
};
pub const pop_dir: [n_pop][dim]i8 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ [_]i8{ 0, 0 }, [_]i8{ 1, 0 }, [_]i8{ 0, 1 }, [_]i8{ -1, 0 }, [_]i8{ 0, -1 }, [_]i8{ 1, 1 }, [_]i8{ -1, 1 }, [_]i8{ -1, -1 }, [_]i8{ 1, -1 } },
};
pub const n_nodes = domain_size[0] * domain_size[1] * (if (dim == 2) 1 else domain_size[2]);
pub const pop_weights: [n_pop]f32 = switch (vel_set_use) {
    VelSet.D2Q9 => .{ 4.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0, 1.0 / 36.0 },
};

// Parameters
pub const tau: f32 = 0.9;
pub const domain_size: [dim]u32 = .{ 32, 32 };
pub const vel_set_use = VelSet.D2Q9;