const std = @import("std");
const utils = @import("utils.zig");
const defs = @import("defines.zig");
const fidx = @import("idx.zig");
const Allocator = std.mem.Allocator;

pub const NodeIBM = struct {
    pos: [defs.dim]f32,
    u_interp: [defs.dim]f32,
    rho_interp: f32,
    area: f32,
    f_spread: [defs.dim]f32,

    pub fn init() NodeIBM {
        const n: NodeIBM = .{
            .pos = .{ 0, 0, 0 },
            .u_interp = .{ 0, 0, 0 },
            .f_spread = .{ 0, 0, 0 },
            .rho_interp = 0,
            .area = 0,
        };
        return n;
    }
};

pub const BodyIBM = struct {
    nodes: []NodeIBM,

    pub fn create_basic_body(alloc: Allocator) !BodyIBM {
        const xmin = 10;
        const xmax = defs.domain_size[0] - 10;
        const ymin = 10;
        const ymax = defs.domain_size[1] - 10;
        const z_use = defs.domain_size[2] / 2;

        const n_nodes = (xmax - xmin) * (ymax - ymin);

        var body_nodes = try alloc.alloc(NodeIBM, n_nodes);
        for (0..n_nodes) |idx| {
            body_nodes[idx] = NodeIBM.init();
        }

        var i: usize = 0;
        for (xmin..xmax) |x| {
            for (ymin..ymax) |y| {
                body_nodes[i].pos = .{ @floatFromInt(x), @floatFromInt(y), z_use };
                body_nodes[i].area = 1;
                i += 1;
            }
        }

        return .{ .nodes = body_nodes };
    }
};

test "create basic body" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const body = try BodyIBM.create_basic_body(allocator);
    for (body.nodes) |node| {
        try std.testing.expectEqual(node.area, 1);
    }
}
