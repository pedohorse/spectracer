const std = @import("std");
const alloc = std.heap.page_allocator;
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});

const LoadingError = error{
    InvalidSyntax,
    LogicError,
    InternalError,
    AllocError,
    FileNotFound,
};

pub fn load_obj(device: embree.RTCDevice, file_path: []const u8) !embree.RTCGeometry {
    var vertices = try std.ArrayList(f32).initCapacity(alloc, 8192);
    defer vertices.deinit();
    var triangles = try std.ArrayList(u32).initCapacity(alloc, 8192);
    defer triangles.deinit();
    var vertex_count: usize = 0;
    var triangle_count: usize = 0;

    {
        var file = std.fs.cwd().openFile(file_path, .{}) catch {
            return LoadingError.FileNotFound;
        };
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();
        var line_buf = try std.ArrayList(u8).initCapacity(alloc, 256);
        defer line_buf.deinit();
        var done = false;

        while (!done) {
            line_buf.clearRetainingCapacity();
            reader.streamUntilDelimiter(line_buf.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    done = true;
                },
                else => {},
            };
            try line_buf.append('\n');
            if (line_buf.items.len > 2) {
                //std.debug.print("dbg: {s}\n", .{line_buf.items});
                if (std.mem.eql(u8, line_buf.items[0..2], "v ")) {
                    vertex_count += 1;
                    var prev_i: usize = 2;
                    var lstate = (enum { skip_spaces, parse_text }).skip_spaces;
                    var values_parsed: u32 = 0;
                    for (line_buf.items[2..], 2..) |c, i| {
                        if ((c == ' ' or c == '\n') and lstate == .parse_text) {
                            const v = try std.fmt.parseFloat(f32, line_buf.items[prev_i..i]);
                            lstate = .skip_spaces;
                            try vertices.append(v);
                            values_parsed += 1;
                        } else if (c != ' ' and lstate == .skip_spaces) {
                            prev_i = i;
                            lstate = .parse_text;
                        }
                    }
                    if (values_parsed != 3 or lstate != .skip_spaces) {
                        return LoadingError.InvalidSyntax;
                    }
                } else if (std.mem.eql(u8, line_buf.items[0..2], "f ")) {
                    // triangulating on the fly
                    var prev_i: usize = 2;
                    var lstate = (enum { skip_spaces, skip_garbage, parse_text }).skip_spaces;
                    var values_parsed: u32 = 0;
                    var vi0: u32 = undefined;
                    var vi1: u32 = undefined;

                    for (line_buf.items[2..], 2..) |c, i| {
                        switch (lstate) {
                            .parse_text => if (c == ' ' or c == '\n' or c == '/') {
                                const v = try std.fmt.parseInt(u32, line_buf.items[prev_i..i], 10) - 1;
                                lstate = if (c == '/') .skip_garbage else .skip_spaces;

                                if (values_parsed == 0) {
                                    triangle_count += 1;
                                    vi0 = v;
                                } else if (values_parsed == 1) {
                                    vi1 = v;
                                } else if (values_parsed > 2) {
                                    try triangles.append(vi0);
                                    try triangles.append(vi1);
                                    triangle_count += 1;
                                }
                                try triangles.append(v);
                                values_parsed += 1;
                                vi1 = v;
                                if (v >= vertices.items.len) {
                                    return LoadingError.LogicError;
                                }
                            },
                            .skip_spaces => if (c != ' ') {
                                prev_i = i;
                                lstate = .parse_text;
                            },
                            .skip_garbage => if (c == ' ') {
                                lstate = .skip_spaces;
                            },
                        }
                    }
                    if (values_parsed < 3 or lstate == .parse_text or triangles.items.len % 3 != 0) {
                        return LoadingError.LogicError;
                    }
                }
            }
        }
    }

    if (vertex_count != vertices.items.len / 3 or vertices.items.len % 3 != 0) {
        return LoadingError.InternalError;
    }
    if (triangle_count != triangles.items.len / 3 or triangles.items.len % 3 != 0) {
        return LoadingError.InternalError;
    }

    std.debug.print("geo {s} has {} verts, {} tris\n", .{ file_path, vertex_count, triangle_count });

    // now to embree part
    var geo = embree.rtcNewGeometry(device, embree.RTC_GEOMETRY_TYPE_TRIANGLE);

    var vertex_buff: [*]f32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_VERTEX, 0, embree.RTC_FORMAT_FLOAT3, 3 * @sizeOf(f32), vertex_count) orelse {
        return LoadingError.AllocError;
    }));
    @memcpy(vertex_buff[0..vertices.items.len], vertices.items);

    var index_buff: [*]u32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_INDEX, 0, embree.RTC_FORMAT_UINT3, 3 * @sizeOf(u32), triangle_count) orelse {
        return LoadingError.AllocError;
    }));
    @memcpy(index_buff[0..triangles.items.len], triangles.items);

    embree.rtcCommitGeometry(geo);
    return geo;
}
