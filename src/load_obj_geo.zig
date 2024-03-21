const std = @import("std");
const log = std.log;
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
    var polygons = try std.ArrayList(u32).initCapacity(alloc, 8192);
    defer polygons.deinit();
    var face_vtx_counts = try std.ArrayList(u32).initCapacity(alloc, 8192);
    defer face_vtx_counts.deinit();
    // var colors = try std.ArrayList(f32).initCapacity(alloc, 8192);
    // defer colors.deinit();
    // var colors = try std.ArrayList(f32).initCapacity(alloc, 8192);
    // defer colors.deinit();
    var vertex_count: usize = 0;
    var primitive_count: usize = 0;

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
                            if (values_parsed == 3) {
                                // for now ignore possible color
                                break;
                            }
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

                    for (line_buf.items[2..], 2..) |c, i| {
                        switch (lstate) {
                            .parse_text => if (c == ' ' or c == '\n' or c == '/') {
                                const v = try std.fmt.parseInt(u32, line_buf.items[prev_i..i], 10) - 1;
                                lstate = if (c == '/') .skip_garbage else .skip_spaces;

                                try polygons.append(v);
                                values_parsed += 1;
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
                    primitive_count += 1;
                    try face_vtx_counts.append(values_parsed);
                    if (values_parsed < 3 or lstate == .parse_text) {
                        return LoadingError.LogicError;
                    }
                }
            }
        }
    }

    if (vertex_count != vertices.items.len / 3 or vertices.items.len % 3 != 0 or face_vtx_counts.items.len != primitive_count) {
        return LoadingError.InternalError;
    }

    log.debug("geo {s} has {} verts, {} prims", .{ file_path, vertex_count, primitive_count });

    // now to embree part
    var geo = embree.rtcNewGeometry(device, embree.RTC_GEOMETRY_TYPE_SUBDIVISION);

    var vertex_buff: [*]f32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_VERTEX, 0, embree.RTC_FORMAT_FLOAT3, 3 * @sizeOf(f32), vertex_count) orelse {
        return LoadingError.AllocError;
    }));
    @memcpy(vertex_buff[0..vertices.items.len], vertices.items);

    var facecnt_buff: [*]u32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_FACE, 0, embree.RTC_FORMAT_UINT, @sizeOf(u32), face_vtx_counts.items.len) orelse {
        return LoadingError.AllocError;
    }));
    @memcpy(facecnt_buff[0..face_vtx_counts.items.len], face_vtx_counts.items);

    var index_buff: [*]u32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_INDEX, 0, embree.RTC_FORMAT_UINT, @sizeOf(u32), polygons.items.len) orelse {
        return LoadingError.AllocError;
    }));
    @memcpy(index_buff[0..polygons.items.len], polygons.items);

    embree.rtcCommitGeometry(geo);
    return geo;
}
