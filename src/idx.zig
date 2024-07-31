const defs = @import("defines.zig");

pub inline fn idx2pos(idx: usize) [defs.dim]u32 {
    if (defs.dim == 2) {
        return .{ @intCast(idx % defs.domain_size[0]), @intCast(idx / defs.domain_size[0]) };
    } else {
        return .{ @intCast(idx % defs.domain_size[0]), @intCast((idx / defs.domain_size[0]) % defs.domain_size[1]), @intCast(idx / (defs.domain_size[0] * defs.domain_size[1])) };
    }
}

pub inline fn pos2idx(pos: [defs.dim]u32) usize {
    if (defs.dim == 2) {
        return pos[0] + pos[1] * defs.domain_size[0];
    } else {
        return pos[0] + defs.domain_size[0] * (pos[1] + pos[2] * defs.domain_size[1]);
    }
}

pub inline fn idxPop(pos: [defs.dim]u32, i: u8) usize {
    return i + defs.n_pop * (pos2idx(pos));
}

test "test Idx" {
    const std = @import("std");
    const assert = std.debug.assert;
    var count: usize = 0;
    for (0..defs.n_nodes) |idx| {
        const pos = idx2pos(idx);
        const retIdx = pos2idx(pos);
        assert(retIdx == idx);
        for (0..defs.dim) |d| {
            assert(pos[d] >= 0);
            assert(pos[d] < defs.domain_size[d]);
        }
        for (0..defs.n_pop) |i| {
            const popIdx = idxPop(pos, @intCast(i));
            assert(count == popIdx);
            count += 1;
        }
    }
}
