const std = @import("std");
const info = std.log.info;

const c = @cImport({
    @cDefine("CL_TARGET_OPENCL_VERSION", "110");
    @cInclude("CL/cl.h");
});

const CLError = error{
    GetPlatformsFailed,
    GetPlatformInfoFailed,
    NoPlatformsFound,
    GetDevicesFailed,
    GetDeviceInfoFailed,
    NoDevicesFound,
    CreateContextFailed,
    CreateCommandQueueFailed,
    CreateProgramFailed,
    BuildProgramFailed,
    FreeProgramFailed,
    CreateKernelFailed,
    FreeKernelFailed,
    SetKernelArgFailed,
    EnqueueNDRangeKernel,
    CreateBufferFailed,
    EnqueueWriteBufferFailed,
    EnqueueReadBufferFailed,
};

pub fn cl_get_device() CLError!c.cl_device_id {
    var platform_ids: [16]c.cl_platform_id = undefined;
    var platform_count: c.cl_uint = undefined;
    if (c.clGetPlatformIDs(platform_ids.len, &platform_ids, &platform_count) != c.CL_SUCCESS) {
        return CLError.GetPlatformsFailed;
    }
    info("{} cl platform(s) found:", .{@as(u32, platform_count)});

    for (platform_ids[0..platform_count], 0..) |id, i| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;
        if (c.clGetPlatformInfo(id, c.CL_PLATFORM_NAME, name.len, &name, &name_len) != c.CL_SUCCESS) {
            return CLError.GetPlatformInfoFailed;
        }
        info("  platform {}: {s}", .{ i, name[0..name_len] });
    }

    if (platform_count == 0) {
        return CLError.NoPlatformsFound;
    }

    info("choosing platform 0...", .{});

    var device_ids: [16]c.cl_device_id = undefined;
    var device_count: c.cl_uint = undefined;
    if (c.clGetDeviceIDs(platform_ids[0], c.CL_DEVICE_TYPE_ALL, device_ids.len, &device_ids, &device_count) != c.CL_SUCCESS) {
        return CLError.GetDevicesFailed;
    }
    info("{} cl device(s) found on platform 0:", .{@as(u32, device_count)});

    for (device_ids[0..device_count], 0..) |id, i| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;
        if (c.clGetDeviceInfo(id, c.CL_DEVICE_NAME, name.len, &name, &name_len) != c.CL_SUCCESS) {
            return CLError.GetDeviceInfoFailed;
        }
        info("  device {}: {s}", .{ i, name[0..name_len] });
    }

    if (device_count == 0) {
        return CLError.NoDevicesFound;
    }

    info("choosing device 0...", .{});

    return device_ids[0];
}

pub const CLBuffer = struct {
    const Self = @This();

    ctx: c.cl_context,
    d_buff: c.cl_mem,
    size: usize,

    pub fn init(size: usize, ctx: c.cl_context) CLError!CLBuffer {
        const input_buffer = c.clCreateBuffer(ctx, c.CL_MEM_READ_WRITE, size, null, null);
        if (input_buffer == null) {
            return CLError.CreateBufferFailed;
        }
        return .{ .ctx = ctx, .d_buff = input_buffer.?, .size = size };
    }

    pub fn free(self: Self) void {
        _ = c.clReleaseMemObject(self.d_buff);
    }

    pub fn read(self: Self, h_buff: ?*anyopaque, cmd_queue: CLQueue) CLError!void {
        // Fill input buffer
        if (c.clEnqueueReadBuffer(cmd_queue.queue, self.d_buff, c.CL_TRUE, 0, self.size, h_buff, 0, null, null) != c.CL_SUCCESS) {
            return CLError.EnqueueReadBufferFailed;
        }
    }

    pub fn write(self: Self, h_buff: ?*const anyopaque, cmd_queue: CLQueue) CLError!void {
        // Fill input buffer
        if (c.clEnqueueWriteBuffer(cmd_queue.queue, self.d_buff, c.CL_TRUE, 0, self.size, h_buff, 0, null, null) != c.CL_SUCCESS) {
            return CLError.EnqueueWriteBufferFailed;
        }
    }
};

pub const CLQueue = struct {
    const Self = @This();

    queue: c.cl_command_queue,

    pub fn init(ctx: c.cl_context, device: c.cl_device_id) CLError!Self {
        const command_queue = c.clCreateCommandQueue(ctx, device, 0, null); // future: last arg is error code
        if (command_queue == null) {
            return CLError.CreateCommandQueueFailed;
        }
        return .{ .queue = command_queue };
    }

    pub fn free(self: Self) void {
        _ = c.clFlush(self.queue);
        _ = c.clFinish(self.queue);
        _ = c.clReleaseCommandQueue(self.queue);
    }
};

test "test OpenCL memory buffer" {
    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const hbuff_write: [3]u8 = .{ 1, 2, 3 };
    var hbuff_read: [3]u8 = undefined;

    const queue = try CLQueue.init(ctx, device);
    var dbuff = try CLBuffer.init(3, ctx);
    defer {
        dbuff.free();
        queue.free();
    }

    try dbuff.write(&hbuff_write, queue);
    try dbuff.read(&hbuff_read, queue);
    _ = c.clFlush(queue.queue);
    _ = c.clFinish(queue.queue);

    try std.testing.expectEqual(1, hbuff_read[0]);
    try std.testing.expectEqual(2, hbuff_read[1]);
    try std.testing.expectEqual(3, hbuff_read[2]);
}

pub const CLProgram = struct {
    const Self = @This();

    program: c.cl_program,

    pub fn init(ctx: c.cl_context, device: c.cl_device_id, program_src_c: []const u8) CLError!Self {
        const program = c.clCreateProgramWithSource(ctx, 1, @ptrCast(@constCast(&program_src_c.ptr)), null, null); // future: last arg is error code
        if (program == null) {
            return CLError.CreateProgramFailed;
        }
        if (c.clBuildProgram(program, 1, &device, null, null, null) != c.CL_SUCCESS) {
            return CLError.BuildProgramFailed;
        }
        return .{ .program = program };
    }

    pub fn free(self: Self) CLError!void {
        if (c.clReleaseProgram(self.program) != c.CL_SUCCESS) {
            return CLError.FreeProgramFailed;
        }
    }
};

test "test OpenCL program" {
    const program_src =
        \\__kernel void square_array(__global int* input_array, __global int* output_array) {
        \\    int i = get_global_id(0);
        \\    int value = input_array[i];
        \\    output_array[i] = value * value;
        \\}
    ;

    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const program = try CLProgram.init(ctx, device, program_src);
    try program.free();
}

pub const CLKernel = struct {
    const Self = @This();

    kernel: c.cl_kernel,

    pub fn init(program: CLProgram, kernel_name: []const u8) CLError!CLKernel {
        const kernel = c.clCreateKernel(program, kernel_name, null);
        if (kernel == null) {
            return CLError.CreateKernelFailed;
        }
        return .{ .kernel = kernel };
    }

    pub fn free(self: Self) CLError!void {
        if (c.clReleaseKernel(self.kernel) != c.CL_SUCCESS) {
            return CLError.FreeKernelFailed;
        }
    }
};

// fn run_test(device: c.cl_device_id) CLError!void {
//     info("** running test **", .{});

//     var input_buffer = c.clCreateBuffer(ctx, c.CL_MEM_READ_ONLY, input_array.len * @sizeOf(i32), null, null);
//     if (input_buffer == null) {
//         return CLError.CreateBufferFailed;
//     }
//     defer _ = c.clReleaseMemObject(input_buffer);

//     var output_buffer = c.clCreateBuffer(ctx, c.CL_MEM_WRITE_ONLY, input_array.len * @sizeOf(i32), null, null);
//     if (output_buffer == null) {
//         return CLError.CreateBufferFailed;
//     }
//     defer _ = c.clReleaseMemObject(output_buffer);

//     // Fill input buffer
//     if (c.clEnqueueWriteBuffer(command_queue, input_buffer, c.CL_TRUE, 0, input_array.len * @sizeOf(i32), &input_array, 0, null, null) != c.CL_SUCCESS) {
//         return CLError.EnqueueWriteBufferFailed;
//     }

//     // Execute kernel
//     if (c.clSetKernelArg(kernel, 0, @sizeOf(c.cl_mem), @ptrCast(&input_buffer)) != c.CL_SUCCESS) {
//         return CLError.SetKernelArgFailed;
//     }
//     if (c.clSetKernelArg(kernel, 1, @sizeOf(c.cl_mem), @ptrCast(&output_buffer)) != c.CL_SUCCESS) {
//         return CLError.SetKernelArgFailed;
//     }

//     var global_item_size: usize = input_array.len;
//     var local_item_size: usize = 64;
//     if (c.clEnqueueNDRangeKernel(command_queue, kernel, 1, null, &global_item_size, &local_item_size, 0, null, null) != c.CL_SUCCESS) {
//         return CLError.EnqueueNDRangeKernel;
//     }

//     var output_array: [1024]i32 = undefined;
//     if (c.clEnqueueReadBuffer(command_queue, output_buffer, c.CL_TRUE, 0, output_array.len * @sizeOf(i32), &output_array, 0, null, null) != c.CL_SUCCESS) {
//         return CLError.EnqueueReadBufferFailed;
//     }

//     info("** done **", .{});

//     info("** results **", .{});

//     for (output_array, 0..) |val, i| {
//         if (i % 100 == 0) {
//             info("{} ^ 2 = {}", .{ i, val });
//         }
//     }

//     info("** done, exiting **", .{});
// }
