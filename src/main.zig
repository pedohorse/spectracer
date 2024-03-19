const std = @import("std");
const print = std.debug.print;
const obj_loader = @import("load_obj_geo.zig");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const Pool = @import("parallel.zig").Pool;
const Color = @import("data_types.zig").Color;

const output_ascii = @import("output_ascii.zig");
const output_png = @import("output_png.zig");

const Err = error{general};

const SceneData = struct {
    scene: embree.RTCScene,
    global_height: usize,
    global_width: usize,
    focal: f32,
};

const ChunkData = struct {
    scene_data: *SceneData,
    intersection_context: *embree.RTCIntersectContext,
    chunk_start_x: usize,
    chunk_start_y: usize,
};

pub fn main() !void {
    var device = embree.rtcNewDevice(null);
    defer embree.rtcReleaseDevice(device);
    var scene = embree.rtcNewScene(device);
    defer embree.rtcReleaseScene(scene);
    var geo = try obj_loader.load_obj(device, "ls_pig.obj");

    _ = embree.rtcAttachGeometry(scene, geo);
    embree.rtcReleaseGeometry(geo);
    embree.rtcCommitScene(scene);

    {
        const alloc: std.mem.Allocator = std.heap.c_allocator;
        const width = 1024;
        const height = 1024;
        var pixels: []Color align(16) = try alloc.alloc(Color, width * height);
        defer alloc.free(pixels);
        //initialize_ray_data(rays, width, height, 0.5);

        var inter_context: embree.RTCIntersectContext align(16) = undefined;
        embree.rtcInitIntersectContext(&inter_context);
        var scene_context = SceneData{
            .scene = scene,
            .focal = 1.5,
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
                chunk_datas[ci].scene_data = &scene_context;
                chunk_datas[ci].chunk_start_x = offset % width;
                chunk_datas[ci].chunk_start_y = offset / width;
                chunk_datas[ci].intersection_context = &inter_context;
                offset += chunk_size;

                //print("{}x{} ", .{ chunk_datas[ci].chunk_start_x, chunk_datas[ci].chunk_start_y });
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

        //output_ascii.preview_ascii(pixels, width, height);
        print("saving picture\n", .{});
        //try output_ascii.save_ascii(pixels, width, height, "outpic.txt");
        try output_png.save_png(pixels, width, height, "outpic.png");
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
    const ortho_width = 0.5;
    const ortho_height = 0.5;
    for (chunks[chunk_id]) |*pixel| {
        const x: f32 = -ortho_width + 2 * ortho_width * (@as(f32, @floatFromInt(pix_x)) / @as(f32, @floatFromInt(width)));
        const y: f32 = ortho_height - 2 * ortho_height * (@as(f32, @floatFromInt(pix_y)) / @as(f32, @floatFromInt(height)));
        const dirlen = @sqrt(x * x + y * y + focal2); // dir may not be normalized, but it's easier if we keep things normalized for ourselves
        rayhit.ray.org_x = 0;
        rayhit.ray.org_y = 0;
        rayhit.ray.org_z = focal;
        rayhit.ray.dir_x = x / dirlen;
        rayhit.ray.dir_y = y / dirlen;
        rayhit.ray.dir_z = -focal / dirlen;
        rayhit.ray.tnear = 0;
        rayhit.ray.mask = 1;
        rayhit.ray.tfar = std.math.inf(f32);
        rayhit.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;

        const val = trace_ray(&rayhit, &chunk_data, randomizer.random(), 0);
        pixel.* = .{ .r = val, .g = val, .b = val };

        pix_x += 1;
        if (pix_x == width) {
            pix_x = 0;
            pix_y += 1;
        }
    }
}

const MAX_BOUNCE = 1;
const SECONDARY_SAMPLES = 16;

fn trace_ray(rayhit: *embree.RTCRayHit, chunk_data: *const ChunkData, rng: std.rand.Random, depth: u32) f32 {
    if (depth > MAX_BOUNCE) {
        return 0.0;
    }
    embree.rtcIntersect1(chunk_data.scene_data.scene, chunk_data.intersection_context, rayhit);
    if (rayhit.hit.geomID == embree.RTC_INVALID_GEOMETRY_ID) {
        // no hit
        //return 0.0;
        // but for now we treat all env as light
        return 2.0 * rayhit.ray.dir_y; // imitate sky light
    }

    // lambert

    const sample_count: usize = SECONDARY_SAMPLES;
    var val: f32 = 0;
    var secondary_rayhit: embree.RTCRayHit align(16) = undefined;
    const eps = 0.0001;
    for (0..sample_count) |_| {
        const normal: @Vector(3, f32) = blk: {
            var vec: @Vector(3, f32) = .{ rayhit.hit.Ng_x, rayhit.hit.Ng_y, rayhit.hit.Ng_z };
            vec /= @splat(@sqrt(@reduce(.Add, vec * vec)));
            break :blk vec;
        };
        const new_dir: @Vector(3, f32) = random_hemisphere(rng.float(f32), rng.float(f32), normal);
        secondary_rayhit.ray.org_x = rayhit.ray.org_x + rayhit.ray.dir_x * rayhit.ray.tfar + eps * normal[0];
        secondary_rayhit.ray.org_y = rayhit.ray.org_y + rayhit.ray.dir_y * rayhit.ray.tfar + eps * normal[1];
        secondary_rayhit.ray.org_z = rayhit.ray.org_z + rayhit.ray.dir_z * rayhit.ray.tfar + eps * normal[2];
        secondary_rayhit.ray.dir_x = new_dir[0];
        secondary_rayhit.ray.dir_y = new_dir[1];
        secondary_rayhit.ray.dir_z = new_dir[2];
        secondary_rayhit.ray.tnear = 0;
        secondary_rayhit.ray.mask = 1;
        secondary_rayhit.ray.tfar = std.math.inf(f32);
        secondary_rayhit.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;
        var new_sample = trace_ray(&secondary_rayhit, chunk_data, rng, depth + 1);
        const dotn = @reduce(.Add, new_dir * normal);
        new_sample *= dotn;
        val += new_sample;
    }
    if (sample_count > 0) {
        val /= @floatFromInt(sample_count);
    }

    // albedo
    val *= 0.99;

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
    var x = @cos(fi);
    var y = @sin(fi);
    var z = -1 + 2 * v;
    var cz = @sqrt(1 - z * z);

    return .{ x * cz, y * cz, z };
}

test "random_hemisphere" {
    var randomizer = std.rand.Xoshiro256.init(132435);
    var rng = randomizer.random();
    const ray1 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 1, 0 });
    const ray2 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, -1, 0 });
    const ray3 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 1, 0, 0 });
    const ray4 = random_hemisphere(rng.float(f32), rng.float(f32), .{ -1, 0, 0 });
    const ray5 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 0, 1 });
    const ray6 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 0, -1 });
    try std.testing.expect(ray1[1] >= 0);
    try std.testing.expect(ray2[1] <= 0);
    try std.testing.expect(ray3[0] >= 0);
    try std.testing.expect(ray4[0] <= 0);
    try std.testing.expect(ray5[2] >= 0);
    try std.testing.expect(ray6[2] <= 0);
}
