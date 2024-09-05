const std = @import("std");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const Allocator = std.mem.Allocator;

const DIRAC_RADIUS = 1.5;

fn dirac_delta(r: f32) f32 {
    const ar = if (r < 0) -r else r;
    if (ar >= 1.5) {
        return 0;
    }
    if (ar >= 0.5) {
        return 9.0 / 8.0 - 3.0 * ar / 2.0 + r * r / 2.0;
    }
    return 0.75 - ar * ar;
}

pub const NodeIBM = struct {
    const Self = @This();

    pos: [defs.dim]f32,
    u_interp: [defs.dim]f32,
    rho_interp: f32,
    area: f32,
    f_spread: [defs.dim]f32,
    dirac_sum: f32,

    pub fn init() NodeIBM {
        const n: NodeIBM = .{
            .pos = .{ 0, 0, 0 },
            .u_interp = .{ 0, 0, 0 },
            .f_spread = .{ 0, 0, 0 },
            .rho_interp = 0,
            .area = 0,
            .dirac_sum = 0,
        };
        return n;
    }

    pub fn interp(self: *Self, rho: []f32, u: [defs.dim][]f32) void {
        const npos = self.pos;
        const r = DIRAC_RADIUS;
        const min_pos: [3]usize = .{ @intFromFloat(@ceil(npos[0] - r)), @intFromFloat(@ceil(npos[1] - r)), @intFromFloat(@ceil(npos[2] - r)) };
        const max_pos: [3]usize = .{ @intFromFloat(@floor(npos[0] + r)), @intFromFloat(@floor(npos[1] + r)), @intFromFloat(@floor(npos[2] + r)) };

        self.rho_interp = 0;
        self.u_interp = .{ 0, 0, 0 };
        self.dirac_sum = 0;
        for (min_pos[2]..max_pos[2] + 1) |z| {
            const pz: f32 = @floatFromInt(z);
            const rz = pz - npos[2];
            const dirac_z = dirac_delta(rz);
            for (min_pos[1]..max_pos[1] + 1) |y| {
                const py: f32 = @floatFromInt(y);
                const ry = py - npos[1];
                const dirac_y = dirac_delta(ry);
                for (min_pos[0]..max_pos[0] + 1) |x| {
                    const px: f32 = @floatFromInt(x);
                    const rx = px - npos[0];
                    const dirac_x = dirac_delta(rx);

                    const lpos: [defs.dim]u32 = .{ @intCast(x), @intCast(y), @intCast(z) };
                    const idx = fidx.pos2idx(lpos);
                    const rho_local = rho[idx];
                    const u_local = .{ u[0][idx], u[1][idx], u[2][idx] };

                    const dirac = dirac_x * dirac_y * dirac_z;

                    self.rho_interp += rho_local * dirac;
                    self.u_interp[0] += u_local[0] * dirac;
                    self.u_interp[1] += u_local[1] * dirac;
                    self.u_interp[2] += u_local[2] * dirac;
                    self.dirac_sum += dirac;
                }
            }
        }
    }

    pub fn update_f_spread(self: *Self) void {
        self.f_spread[0] = 2 * self.rho_interp * (-self.u_interp[0]) * self.area * defs.forces_relaxation_factor;
        self.f_spread[1] = 2 * self.rho_interp * (-self.u_interp[1]) * self.area * defs.forces_relaxation_factor;
        self.f_spread[2] = 2 * self.rho_interp * (-self.u_interp[2]) * self.area * defs.forces_relaxation_factor;
    }

    pub fn spread(self: Self, force: [defs.dim][]f32) void {
        const npos = self.pos;
        const r = DIRAC_RADIUS;
        const min_pos: [3]usize = .{ @intFromFloat(@ceil(npos[0] - r)), @intFromFloat(@ceil(npos[1] - r)), @intFromFloat(@ceil(npos[2] - r)) };
        const max_pos: [3]usize = .{ @intFromFloat(@floor(npos[0] + r)), @intFromFloat(@floor(npos[1] + r)), @intFromFloat(@floor(npos[2] + r)) };

        for (min_pos[2]..max_pos[2] + 1) |z| {
            const pz: f32 = @floatFromInt(z);
            const rz = pz - npos[2];
            const dirac_z = dirac_delta(rz);
            for (min_pos[1]..max_pos[1] + 1) |y| {
                const py: f32 = @floatFromInt(y);
                const ry = py - npos[1];
                const dirac_y = dirac_delta(ry);
                for (min_pos[0]..max_pos[0] + 1) |x| {
                    const px: f32 = @floatFromInt(x);
                    const rx = px - npos[0];
                    const dirac_x = dirac_delta(rx);

                    const lpos: [defs.dim]u32 = .{ @intCast(x), @intCast(y), @intCast(z) };
                    const idx = fidx.pos2idx(lpos);

                    const dirac = dirac_x * dirac_y * dirac_z;

                    force[0][idx] += self.f_spread[0] * dirac;
                    force[1][idx] += self.f_spread[1] * dirac;
                    force[2][idx] += self.f_spread[2] * dirac;
                }
            }
        }
    }
};

pub const BodyIBM = struct {
    const Self = @This();

    nodes: []NodeIBM,

    pub fn create_basic_body(alloc: Allocator) !BodyIBM {
        const xmin = 10;
        const xmax = defs.domain_size[0] - 10;
        const zmin = 10;
        const zmax = defs.domain_size[1] - 10;
        const y_use = 5;

        const n_nodes = (xmax - xmin) * (zmax - zmin);

        var body_nodes = try alloc.alloc(NodeIBM, n_nodes);
        for (0..n_nodes) |idx| {
            body_nodes[idx] = NodeIBM.init();
        }

        var i: usize = 0;
        for (xmin..xmax) |x| {
            for (zmin..zmax) |z| {
                body_nodes[i].pos = .{ @floatFromInt(x), y_use, @floatFromInt(z) };
                body_nodes[i].area = 1;
                i += 1;
            }
        }

        return .{ .nodes = body_nodes };
    }

    pub fn export_csv(self: Self, allocator: Allocator, path: []const u8) !void {
        var data_wr = std.ArrayList(u8).init(allocator);
        try data_wr.appendSlice("x,y,z,rho,ux,uy,uz,fx,fy,fz\n");
        for (self.nodes) |n| {
            try utils.appendFormatted(&data_wr, "{}, {}, {}, {}, {}, {}, {}, {}, {}, {}\n", .{
                n.pos[0],
                n.pos[1],
                n.pos[2],
                n.rho_interp,
                n.u_interp[0],
                n.u_interp[1],
                n.u_interp[2],
                n.f_spread[0],
                n.f_spread[1],
                n.f_spread[2],
            });
        }
        try utils.writeArrayListToFile(path, data_wr.items);
        data_wr.clearAndFree();
    }

    pub fn interpolate_spread(self: Self, rho: []f32, u: [defs.dim][]f32, force: [defs.dim][]f32) void {
        for (0..self.nodes.len) |idx| {
            self.nodes[idx].interp(rho, u);
            self.nodes[idx].update_f_spread();
            self.nodes[idx].spread(force);
        }
    }

    pub fn run_ibm(self: *const Self, rho: []f32, u: [defs.dim][]f32, force: [defs.dim][]f32) void {
        self.interpolate_spread(rho, u, force);
    }
};

test "create basic body" {
    const allocator = std.testing.allocator;

    const body = try BodyIBM.create_basic_body(allocator);
    defer allocator.free(body.nodes);
    for (body.nodes) |node| {
        try std.testing.expectEqual(node.area, 1);
    }
}

test "interpolate body" {
    const lbm = @import("lbm.zig");
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // const allocator = std.testing.allocator;

    const body = try BodyIBM.create_basic_body(allocator);
    defer allocator.free(body.nodes);

    const lbm_arrays = try lbm.allocate_arrs(&allocator);
    lbm_arrays.initialize();

    body.interpolate_spread(lbm_arrays.rho, lbm_arrays.u, lbm_arrays.force_ibm);

    for (body.nodes) |node| {
        try std.testing.expectApproxEqAbs(1, node.dirac_sum, 0.01);
    }
}

test "spread body" {
    const lbm = @import("lbm.zig");
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const body = try BodyIBM.create_basic_body(allocator);
    defer allocator.free(body.nodes);

    const lbm_arrays = try lbm.allocate_arrs(&allocator);
    lbm_arrays.initialize();

    body.run_ibm(lbm_arrays.rho, lbm_arrays.u, lbm_arrays.force_ibm);
}
