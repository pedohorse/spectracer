const std = @import("std");
const print = std.debug.print;
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const Pool = @import("parallel.zig").Pool;

const Err = error{general};

const SceneData = struct {
    scene: embree.RTCScene,
    global_height: usize,
    global_width: usize,
    focal: f32,
};

const Vec2 = struct {
    x: f32,
    y: f32,
};

const Color = struct {
    r: f32,
    g: f32,
    b: f32,
};

const ChunkData = struct {
    scene_data: *SceneData,
    intersection_context: *embree.RTCIntersectContext,
    chunk_start_x: usize,
    chunk_start_y: usize,
};

pub fn main() !void {
    var device = embree.rtcNewDevice(null);
    var scene = embree.rtcNewScene(device);
    var geo = embree.rtcNewGeometry(device, embree.RTC_GEOMETRY_TYPE_TRIANGLE);

    var vertex_buff: [*]f32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_VERTEX, 0, embree.RTC_FORMAT_FLOAT3, 3 * @sizeOf(f32), 3) orelse {
        return Err.general;
    }));
    vertex_buff[0..9].* = .{
        0.0, 0.0, 1.0,
        1.0, 0.0, 1.0,
        0.0, 1.0, 1.0,
    };
    var index_buff: [*]u32 = @ptrCast(@alignCast(embree.rtcSetNewGeometryBuffer(geo, embree.RTC_BUFFER_TYPE_INDEX, 0, embree.RTC_FORMAT_UINT3, 3 * @sizeOf(u32), 1)));
    index_buff[0..3].* = .{
        0, 1, 2,
    };

    embree.rtcCommitGeometry(geo);
    _ = embree.rtcAttachGeometry(scene, geo);
    embree.rtcReleaseGeometry(geo);
    embree.rtcCommitScene(scene);

    {
        const alloc: std.mem.Allocator = std.heap.c_allocator;
        const width = 100;
        const height = 100;
        var pixels: []Color align(16) = try alloc.alloc(Color, width * height);
        defer alloc.free(pixels);
        //initialize_ray_data(rays, width, height, 0.5);

        var inter_context: embree.RTCIntersectContext align(16) = undefined;
        embree.rtcInitIntersectContext(&inter_context);
        var scene_context = SceneData{
            .scene = scene,
            .focal = 0.5,
            .global_width = width,
            .global_height = height,
        };

        var chunks: [][]Color = undefined;
        var chunk_datas: []ChunkData = undefined;
        {
            const chunk_size = 100;
            var chunk_count = pixels.len / chunk_size;
            if (pixels.len % chunk_size != 0) {
                chunk_count += 1;
            }
            std.log.debug("chunk count: {}", .{chunk_count});

            chunks = try alloc.alloc([]Color, chunk_count);
            chunk_datas = try alloc.alloc(ChunkData, chunk_count);
            var offset: usize = 0;
            for (0..chunk_count) |ci| {
                chunks[ci] = pixels[offset..@min(pixels.len, offset + chunk_size)];
                offset += chunk_size;
                chunk_datas[ci].scene_data = &scene_context;
                chunk_datas[ci].chunk_start_x = offset % width;
                chunk_datas[ci].chunk_start_y = offset / width;
                chunk_datas[ci].intersection_context = &inter_context;
            }
        }
        defer alloc.free(chunks);
        defer alloc.free(chunk_datas);

        {
            var thread_pool = Pool{};
            try thread_pool.init(alloc);
            defer thread_pool.deinit();

            //thread_pool.parallel_for([]embree.RTCRayHit, SceneData, 0, chunks.len, chunks, &scene_context, &trace_chunk);
            thread_pool.parallel_for([]Color, []ChunkData, 0, chunks.len, chunks, &chunk_datas, &trace_chunk2);
        }

        {
            // sorta preview
            for (0..height) |h| {
                for (0..width) |w| {
                    print("{s}", .{if (pixels[h * width + w].r < 0.9) "8" else "-"});
                }
                print("\n", .{});
            }
        }
    }
}

// fn initialize_ray_data(rays: []embree.RTCRayHit, width: usize, height: usize, focal_dist: f32) void {
//     // for now it's orthographic for test
//     // TODO: make parallel

//     const ortho_width = 1.0;
//     const ortho_height = 1.0;
//     for (0..height) |h| {
//         const offset = h * width;
//         const y: f32 = -ortho_height + 2 * ortho_height * (@as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(height)));
//         for (0..width) |w| {
//             var x = -ortho_width + 2 * ortho_width * (@as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(width)));
//             var ray: *embree.RTCRayHit = &rays[offset + w];
//             const dirlen = std.math.sqrt(x * x + y * y + focal_dist * focal_dist); // dir may not be normalized, but it's easier if we keep things normalized for ourselves
//             ray.ray.org_x = 0;
//             ray.ray.org_y = 0;
//             ray.ray.org_z = -focal_dist;
//             ray.ray.dir_x = x / dirlen;
//             ray.ray.dir_y = y / dirlen;
//             ray.ray.dir_z = focal_dist / dirlen;
//             ray.ray.tnear = 0;
//             ray.ray.mask = 1;
//             ray.ray.tfar = std.math.inf(f32);
//             ray.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;
//         }
//     }
// }

// fn trace_chunk(chunks: [][]embree.RTCRayHit, chunk_id: usize, scene_data: ?*SceneData) void {
//     for (chunks[chunk_id]) |*ray| {
//         //val.* += 1.2 * @as(f32, @floatFromInt(chunk_id));
//         embree.rtcIntersect1(scene_data.?.scene, scene_data.?.intersection_context, ray);
//     }
// }

fn trace_chunk2(chunks: [][]Color, chunk_id: usize, chunk_datas: ?*[]ChunkData) void {
    var randomizer = std.rand.Xoshiro256.init(chunk_id + 132435);
    var rayhit: embree.RTCRayHit align(16) = undefined;
    // starting pixel of the chunk
    const chunk_data = chunk_datas.?.*[chunk_id];
    var pix_x = chunk_data.chunk_start_x;
    var pix_y = chunk_data.chunk_start_y;
    const focal = chunk_data.scene_data.focal;
    const focal2 = focal * focal;
    const width = chunk_data.scene_data.global_width;
    const height = chunk_data.scene_data.global_height;
    const ortho_width = 1.0;
    const ortho_height = 1.0;
    for (chunks[chunk_id]) |*pixel| {
        const x: f32 = -ortho_width + 2 * ortho_width * (@as(f32, @floatFromInt(pix_x)) / @as(f32, @floatFromInt(width)));
        const y: f32 = -ortho_height + 2 * ortho_height * (@as(f32, @floatFromInt(pix_y)) / @as(f32, @floatFromInt(height)));
        const dirlen = std.math.sqrt(x * x + y * y + focal2); // dir may not be normalized, but it's easier if we keep things normalized for ourselves
        rayhit.ray.org_x = 0;
        rayhit.ray.org_y = 0;
        rayhit.ray.org_z = -focal;
        rayhit.ray.dir_x = x / dirlen;
        rayhit.ray.dir_y = y / dirlen;
        rayhit.ray.dir_z = focal / dirlen;
        rayhit.ray.tnear = 0;
        rayhit.ray.mask = 1;
        rayhit.ray.tfar = std.math.inf(f32);
        rayhit.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;

        const val = trace_ray(&rayhit, &chunk_data, randomizer.random());
        pixel.* = .{ .r = val, .g = val, .b = val };

        pix_x += 1;
        if (pix_x == width) {
            pix_x = 0;
            pix_y += 1;
        }
    }
}

fn trace_ray(rayhit: *embree.RTCRayHit, chunk_data: *const ChunkData, rng: std.rand.Random) f32 {
    embree.rtcIntersect1(chunk_data.scene_data.scene, chunk_data.intersection_context, rayhit);
    if (rayhit.hit.geomID == embree.RTC_INVALID_GEOMETRY_ID) {
        // no hit
        //return 0.0;
        // but for now we treat all env as light
        return 1.0;
    }

    // lambert

    const sample_count: usize = 1;
    var val: f32 = 0;
    var secondary_rayhit: embree.RTCRayHit align(16) = undefined;
    for (0..sample_count) |_| {
        const new_dir = random_hemisphere(rng.float(f32), rng.float(f32), .{ rayhit.hit.Ng_x, rayhit.hit.Ng_y, rayhit.hit.Ng_z });
        secondary_rayhit.ray.org_x = rayhit.ray.org_x + rayhit.ray.dir_x * rayhit.ray.tfar;
        secondary_rayhit.ray.org_y = rayhit.ray.org_y + rayhit.ray.dir_y * rayhit.ray.tfar;
        secondary_rayhit.ray.org_z = rayhit.ray.org_z + rayhit.ray.dir_z * rayhit.ray.tfar;
        secondary_rayhit.ray.dir_x = new_dir[0];
        secondary_rayhit.ray.dir_y = new_dir[1];
        secondary_rayhit.ray.dir_z = new_dir[2];
        secondary_rayhit.ray.tnear = 0;
        secondary_rayhit.ray.mask = 1;
        secondary_rayhit.ray.tfar = std.math.inf(f32);
        secondary_rayhit.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;
        val += trace_ray(&secondary_rayhit, chunk_data, rng);
    }
    val /= @floatFromInt(sample_count);

    // albedo
    val *= 0.5;

    return val;
}

fn random_hemisphere(u: f32, v: f32, normal: @Vector(3, f32)) @Vector(3, f32) {
    const sample = random_sphere(u, v);
    return if (@reduce(.Add, sample * normal) < 0)
        -sample
    else
        sample;
}

fn random_sphere(u: f32, v: f32) @Vector(3, f32) {
    const fi = u * 2 * std.math.pi;
    var x = std.math.cos(fi);
    var y = std.math.sin(fi);
    var z = -1 + 2 * v;
    var cz = std.math.sqrt(1 - z * z);

    return .{ x * cz, y * cz, z };
}
