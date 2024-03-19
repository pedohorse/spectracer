const std = @import("std");
const Thread = std.Thread;

pub const Pool = struct {
    threads: []std.Thread = undefined,
    alloc: std.mem.Allocator = undefined,
    data: *anyopaque = undefined,
    user_data: ?*anyopaque = undefined,
    orig_slice_len: usize = 0,
    func: *const fn (*anyopaque, usize, usize, ?*anyopaque) void = undefined,
    range_start: usize = 0,
    range_end: usize = 0,
    data_provided: []bool = undefined,

    mutex: Thread.Mutex = .{},
    cond: Thread.Condition = .{},
    closing: bool = false,

    pub fn init(self: *Pool, alloc: std.mem.Allocator) !void {
        const thread_count = try Thread.getCpuCount();
        std.debug.print("threadpool started with {} threads\n", .{thread_count});
        var threads: []Thread = try alloc.alloc(Thread, thread_count);
        var thread_triggers: []bool = try alloc.alloc(bool, thread_count);
        @memset(thread_triggers, false);

        self.* = .{
            .threads = threads,
            .alloc = alloc,
            .data_provided = thread_triggers,
        };

        // start threads
        const config = Thread.SpawnConfig{};
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(config, thread_loop, .{ self, i, thread_count });
        }
    }

    pub fn deinit(self: *Pool) void {
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closing = true;
        }
        self.cond.broadcast();

        for (self.threads) |*thread| {
            thread.join();
            //thread.* = undefined;
        }
        self.alloc.free(self.threads);
        self.alloc.free(self.data_provided);
    }

    pub fn parallel_for(self: *Pool, comptime T: type, comptime D: type, start: usize, end: usize, data: []T, user_data: ?*D, comptime func: *const fn (data: []T, elem: usize, userdata: ?*D) void) void {
        const func_wrapper = struct {
            fn run(func_data: *anyopaque, func_data_len: usize, elem: usize, func_user_data: ?*anyopaque) void {
                func(
                    @as([*]T, @ptrCast(@alignCast(func_data)))[0..func_data_len],
                    elem,
                    @ptrCast(@alignCast(func_user_data)),
                );
            }
        }.run;

        {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.data = @ptrCast(data);
            self.user_data = @ptrCast(user_data);
            self.orig_slice_len = data.len;
            self.func = &func_wrapper;
            self.range_start = start;
            self.range_end = end;
            for (self.data_provided) |*dp| {
                dp.* = true;
            }
        }
        self.cond.broadcast();

        // now wait for finish
        self.mutex.lock();
        defer self.mutex.unlock();
        main: while (true) {
            for (self.data_provided) |dp| {
                if (dp) {
                    // means some thread is not finished yet
                    self.cond.wait(&self.mutex);
                    continue :main;
                }
            }
            break;
        }
    }

    fn thread_loop(self: *Pool, tid: usize, tcount: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            if (!self.data_provided[tid]) {
                self.cond.wait(&self.mutex);
            }
            if (self.closing) {
                break;
            }
            if (self.data_provided[tid]) {
                {
                    self.mutex.unlock();
                    defer self.mutex.lock();

                    const size = self.range_end - self.range_start;
                    const wg_size = blk: {
                        var foo = @max(1, size / tcount);
                        if (size % tcount != 0) {
                            foo += 1;
                        }
                        break :blk foo;
                    };
                    const start = self.range_start + tid * wg_size;
                    const end = @max(start, @min(self.range_end, start + wg_size));

                    for (start..end) |i| {
                        self.func(self.data, self.orig_slice_len, i, self.user_data);
                    }
                }
                self.data_provided[tid] = false;
                self.cond.broadcast(); // would signal, but other threads might already be waiting
            }
        }
    }
};

test "parallel_for" {
    const foo = struct {
        fn foo(data: []f32, i: usize, user_data: ?*f32) void {
            std.log.warn("i={}", .{i});
            data[i] += @floatFromInt(i);
            if (user_data) |d| {
                data[i] += d.*;
            }
        }
    }.foo;
    var pool: Pool = .{};
    try pool.init(std.testing.allocator);
    defer pool.deinit();

    const datasize = 1000;
    var data: [datasize]f32 = .{42} ** datasize;
    var user_data: f32 = 5;
    pool.parallel_for(
        f32,
        f32,
        0,
        datasize,
        &data,
        &user_data,
        &foo,
    );

    for (data, 0..) |val, i| {
        try std.testing.expectEqual(42.0 + user_data + @as(f32, @floatFromInt(i)), val);
    }
}
