const std = @import("std");
const log = std.log;
const scene_stuff = @import("scene.zig");
const shaders = @import("shader.zig");
const SceneDescription = @import("scene_data.zig").SceneDescription;
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

pub fn load_obj_scene(device: embree.RTCDevice, scene_dir_path: []const u8) !scene_stuff.Scene {
    // check if json file is present
    var dir = std.fs.cwd().openDir(scene_dir_path, .{}) catch {
        return LoadingError.FileNotFound;
    };
    defer dir.close();

    _ = dir.statFile("scene.json") catch {
        return load_obj_scene_no_json(device, dir);
    };
    // otherwise scene.json file exists
    return load_obj_scene_json(device, dir);
}

pub fn load_obj_scene_json(device: embree.RTCDevice, scene_dir: std.fs.Dir) !scene_stuff.Scene {
    var file = try scene_dir.openFile("scene.json", .{});
    defer file.close();

    const contents = try file.readToEndAlloc(alloc, 1_000_000_000);

    var scene_desc = std.json.parseFromSlice(SceneDescription, alloc, contents, .{ .ignore_unknown_fields = true }) catch |err| {
        switch (err) {
            error.SyntaxError, error.UnexpectedEndOfInput => {
                std.log.err("bad scene file", .{});
            },
            else => {
                std.log.err("error parsing scene", .{});
            },
        }
        return err;
    };
    defer scene_desc.deinit();

    // ok, scene parsed
    var scene = scene_stuff.Scene.init(alloc, device);

    for (scene_desc.value.objects) |object| {
        var geo = try load_obj(device, scene_dir, object.file);
        embree.rtcSetGeometryTessellationRate(geo, object.tesselation);
        embree.rtcCommitGeometry(geo);

        const geo_id: u32 = embree.rtcAttachGeometry(scene.embree_scene, geo);
        try scene.assign_material(geo_id, switch (object.mat) {
            .lambert => |mat| try scene.new_lambert(.{ .r = mat.cr, .g = mat.cg, .b = mat.cb }),
            .light => |mat| try scene.new_light(.{ .r = mat.er, .g = mat.eg, .b = mat.eb }),
            .glass => |mat| try scene.new_refract(mat.ior_base, mat.ior_shift),
            .mirror => try scene.new_reflect(),
        });
    }
    scene.commit();
    return scene;
}

pub fn load_obj_scene_no_json(device: embree.RTCDevice, scene_dir: std.fs.Dir) !scene_stuff.Scene {
    var idir = scene_dir.openIterableDir(".", .{}) catch {
        return LoadingError.FileNotFound;
    };
    defer idir.close();

    //var rtc_scene = embree.rtcNewScene(device);
    //var matmap = std.AutoHashMap(u32, shaders.Shader).init(alloc);
    var scene = scene_stuff.Scene.init(alloc, device);

    var dir_iter = idir.iterateAssumeFirstIteration();
    var name_parts = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    defer name_parts.deinit();
    while (try dir_iter.next()) |entry| {
        // we cannot rely on entry.kind on some fs, some systems, where stat call is expensive,
        // according to some implementation detail man pags (getdents64)
        const kind =
            if (entry.kind != .unknown)
            entry.kind
        else blk: {
            const fstat = scene_dir.statFile(entry.name) catch continue;
            break :blk fstat.kind;
        };

        if (kind != .file) continue;

        // figure out material from name
        const name_no_ext = entry.name[0 .. std.mem.lastIndexOf(u8, entry.name, ".") orelse entry.name.len];

        name_parts.clearRetainingCapacity();
        {
            var last_underscore: usize = @as(usize, 0) -% 1;
            var underscore: usize = 0;
            while (underscore < name_no_ext.len) {
                const next_pos = last_underscore +% 1;
                underscore = (std.mem.indexOf(u8, name_no_ext[next_pos..], "_") orelse (name_no_ext.len - next_pos)) + next_pos;
                try name_parts.append(name_no_ext[next_pos..underscore]);
                last_underscore = underscore;
            }
        }

        if (name_parts.items.len == 0) continue;

        const obj_name = name_parts.items[0];
        _ = obj_name; // TODO: figure out why we need name
        const mat_name = if (name_parts.items.len > 1) name_parts.items[1] else "lambert";
        const attrib_start_i = 2;

        var geo = try load_obj(device, scene_dir, entry.name);
        if (std.mem.eql(u8, name_parts.getLast(), "h")) { // hard geo
            embree.rtcSetGeometryTessellationRate(geo, 0.0);
        } else {
            embree.rtcSetGeometryTessellationRate(geo, 16.0);
        }
        embree.rtcCommitGeometry(geo);

        const geo_id: u32 = embree.rtcAttachGeometry(scene.embree_scene, geo);
        try scene.assign_material(geo_id, if (std.mem.eql(u8, mat_name, "light")) blk: {
            var r: f32 = 10.0; // default light color
            var g: f32 = 9.0;
            var b: f32 = 8.0;
            if (name_parts.items.len >= attrib_start_i + 3) {
                r = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 0]) catch r;
                g = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 1]) catch g;
                b = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 2]) catch b;
            }
            break :blk try scene.new_light(.{ .r = r, .g = g, .b = b });
        } else if (std.mem.eql(u8, mat_name, "glass")) blk: {
            var ior_base: f32 = 1.2;
            var ior_shift: f32 = 0.4;
            if (name_parts.items.len >= attrib_start_i + 2) {
                ior_base = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 0]) catch ior_base;
                ior_shift = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 1]) catch ior_shift;
            }
            break :blk try scene.new_refract(ior_base, ior_shift);
        } else if (std.mem.eql(u8, mat_name, "mirror")) blk: {
            break :blk try scene.new_reflect();
        } else blk: {
            var r: f32 = 0.75; // default surface color
            var g: f32 = 0.75;
            var b: f32 = 0.75;
            if (name_parts.items.len >= attrib_start_i + 3) {
                r = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 0]) catch r;
                g = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 1]) catch g;
                b = std.fmt.parseFloat(f32, name_parts.items[attrib_start_i + 2]) catch b;
            }
            break :blk try scene.new_lambert(.{ .r = r, .g = g, .b = b });
        });
        log.debug("obj is |{s}|", .{mat_name});
        embree.rtcReleaseGeometry(geo);
    }

    scene.commit();
    return scene;
}

pub fn load_obj(device: embree.RTCDevice, dir: std.fs.Dir, file_path: []const u8) !embree.RTCGeometry {
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
        var file = dir.openFile(file_path, .{}) catch {
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
