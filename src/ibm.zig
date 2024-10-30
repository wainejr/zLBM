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
};

test "create basic body" {
    const allocator = std.testing.allocator;

    const body = try BodyIBM.create_basic_body(allocator);
    defer allocator.free(body.nodes);
    for (body.nodes) |node| {
        try std.testing.expectEqual(node.area, 1);
    }
}
