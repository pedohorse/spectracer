const std = @import("std");
const print = std.debug.print;
const obj_loader = @import("load_obj_geo.zig");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const Pool = @import("parallel.zig").Pool;
const Color = @import("data_types.zig").Color;
const Spectrum = @import("spectrum.zig").Spectrum;
const Scene = @import("scene.zig").Scene;
const random_hemisphere = @import("random.zig").random_hemisphere;

const output_ascii = @import("output_ascii.zig");
const output_png = @import("output_png.zig");

const logging = @import("log.zig");
pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = logging.logFn;
};

const Err = error{general};

const SceneData = struct {
    scene: *Scene,
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
    logging.init_logging();

    var device = embree.rtcNewDevice(null);
    defer embree.rtcReleaseDevice(device);
    std.log.debug("loading scene", .{});
    var scene = try obj_loader.load_obj_scene(device, "scene");
    defer scene.deinit();
    std.log.debug("scene loaded", .{});

    {
        std.log.debug("preparing data", .{});
        const alloc: std.mem.Allocator = std.heap.c_allocator;
        const width = 1024;
        const height = 1024;
        var pixels: []Color align(16) = try alloc.alloc(Color, width * height);
        defer alloc.free(pixels);

        var inter_context: embree.RTCIntersectContext align(16) = undefined;
        embree.rtcInitIntersectContext(&inter_context);
        var scene_context = SceneData{
            .scene = &scene,
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
            }
        }
        defer alloc.free(chunks);
        defer alloc.free(chunk_datas);

        {
            var thread_pool = Pool{};
            try thread_pool.init(alloc);
            defer thread_pool.deinit();

            std.log.debug("render started", .{});
            thread_pool.parallel_for([]Color, []ChunkData, 0, chunks.len, chunks, &chunk_datas, &trace_chunk2);
            std.log.debug("render finished", .{});
        }

        //output_ascii.preview_ascii(pixels, width, height);
        std.log.debug("saving picture", .{});
        //try output_ascii.save_ascii(pixels, width, height, "outpic.txt");
        try output_png.save_png(pixels, width, height, "outpic.png");
        std.log.debug("done", .{});
    }
}

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
        var avg_val: Spectrum = Spectrum.new_black();
        for (0..PRIMARY_SAMPLES * PRIMARY_SAMPLES) |sample_i| {
            const xs_offset: f32 = (@as(f32, @floatFromInt(sample_i % PRIMARY_SAMPLES)) + 0.5) / PRIMARY_SAMPLES - 0.5;
            const ys_offset: f32 = (@as(f32, @floatFromInt(sample_i / PRIMARY_SAMPLES)) + 0.5) / PRIMARY_SAMPLES - 0.5;

            const x: f32 = -ortho_width + 2 * ortho_width * ((xs_offset + @as(f32, @floatFromInt(pix_x))) / @as(f32, @floatFromInt(width)));
            const y: f32 = ortho_height - 2 * ortho_height * ((ys_offset + @as(f32, @floatFromInt(pix_y))) / @as(f32, @floatFromInt(height)));
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

            const val = trace_ray(Spectrum, &rayhit, 0.0, &chunk_data, randomizer.random(), 0);
            avg_val.add(&val);
        }
        avg_val.scale(1.0 / PRIMARY_SAMPLES * PRIMARY_SAMPLES);
        //pixel.* = .{ .r = avg_val, .g = avg_val, .b = avg_val };
        pixel.* = avg_val.to_color();

        pix_x += 1;
        if (pix_x == width) {
            pix_x = 0;
            pix_y += 1;
        }
    }
}

const MAX_BOUNCE = 1;
const SECONDARY_SAMPLES = 16;
const PRIMARY_SAMPLES = 1;

fn trace_ray(comptime T: type, rayhit: *embree.RTCRayHit, frequency: f32, chunk_data: *const ChunkData, rng: std.rand.Random, depth: u32) T {
    if (depth > MAX_BOUNCE) {
        if (T == Spectrum) {
            return Spectrum.new_black();
        } else if (T == f32) {
            return 0.0;
        } else unreachable;
    }
    embree.rtcIntersect1(chunk_data.scene_data.scene.embree_scene, chunk_data.intersection_context, rayhit);
    if (rayhit.hit.geomID == embree.RTC_INVALID_GEOMETRY_ID) {
        // no hit
        //return 0.0;
        // but for now we treat all env as light
        const val = 0.0; // 2.0 * rayhit.ray.dir_y; // imitate sky light
        if (T == Spectrum) {
            return Spectrum.new_uniform(val);
        } else if (T == f32) {
            return val;
        } else unreachable;
    } else if (chunk_data.scene_data.scene.material_map.get(rayhit.hit.geomID) orelse .lambert == .light) {
        const val = 10.0; // TODO: take intensity from light properties
        if (T == Spectrum) {
            return Spectrum.new_uniform(val);
        } else if (T == f32) {
            return val;
        } else unreachable;
    }

    // lambert

    var per_freq_bsdf = false;

    const sample_count: usize = SECONDARY_SAMPLES;
    var val: T = if (T == Spectrum) Spectrum.new_black() else if (T == f32) 0.0 else unreachable;
    var secondary_rayhit: embree.RTCRayHit align(16) = undefined;
    const eps = 0.0001;
    for (0..sample_count) |_| {
        const normal: @Vector(3, f32) = blk: {
            var vec: @Vector(3, f32) = .{ rayhit.hit.Ng_x, rayhit.hit.Ng_y, rayhit.hit.Ng_z };
            vec /= @splat(@sqrt(@reduce(.Add, vec * vec)));
            break :blk vec;
        };
        if (T == Spectrum) {
            if (per_freq_bsdf) {
                // case when spectrum needs frequency-dependent bsdf sampling
                const ru = rng.float(f32);
                const rv = rng.float(f32);
                for (&val.values, 0..) |*x, i| {
                    const freq: f32 = Spectrum.start_freq + Spectrum.freq_step * @as(f32, @floatFromInt(i));
                    // TODO: generalize ray sampling func
                    const new_dir: @Vector(3, f32) = random_hemisphere(ru, rv, normal);
                    const dotn = @reduce(.Add, new_dir * normal);
                    init_secondary_rayhit(&secondary_rayhit, rayhit, new_dir, normal, eps);

                    const sample = trace_ray(f32, &secondary_rayhit, freq, chunk_data, rng, depth + 1);
                    x.* += sample * dotn;
                }
            } else {
                // case when ray does not need frequency-dependent bsdf sampling
                const new_dir: @Vector(3, f32) = random_hemisphere(rng.float(f32), rng.float(f32), normal);
                const dotn = @reduce(.Add, new_dir * normal);
                init_secondary_rayhit(&secondary_rayhit, rayhit, new_dir, normal, eps);

                const new_sample: T = trace_ray(T, &secondary_rayhit, frequency, chunk_data, rng, depth + 1);
                for (&val.values, new_sample.values) |*x, y| {
                    x.* += y * dotn;
                }
            }
        } else if (T == f32) {
            // case of single frequency ray sampling
            const new_dir: @Vector(3, f32) = random_hemisphere(rng.float(f32), rng.float(f32), normal);
            const dotn = @reduce(.Add, new_dir * normal);
            init_secondary_rayhit(&secondary_rayhit, rayhit, new_dir, normal, eps);

            const new_sample: T = trace_ray(T, &secondary_rayhit, frequency, chunk_data, rng, depth + 1);
            val += new_sample * dotn;
        } else unreachable;
    }

    // TODO: get this material's blocking spectrum
    const tmp_spec_mod = 0.99;

    if (sample_count > 0) {
        const total_weight: f32 = @floatFromInt(sample_count);
        if (T == Spectrum) {
            val.scale(tmp_spec_mod / total_weight);
        } else if (T == f32) {
            val /= total_weight;
            val *= tmp_spec_mod;
        } else unreachable;
    }

    return val;
}

fn init_secondary_rayhit(secondary_rayhit: *embree.RTCRayHit, rayhit: *const embree.RTCRayHit, new_dir: @Vector(3, f32), normal: @Vector(3, f32), eps: f32) void {
    secondary_rayhit.*.ray.org_x = rayhit.ray.org_x + rayhit.ray.dir_x * rayhit.ray.tfar + eps * normal[0];
    secondary_rayhit.*.ray.org_y = rayhit.ray.org_y + rayhit.ray.dir_y * rayhit.ray.tfar + eps * normal[1];
    secondary_rayhit.*.ray.org_z = rayhit.ray.org_z + rayhit.ray.dir_z * rayhit.ray.tfar + eps * normal[2];
    secondary_rayhit.*.ray.dir_x = new_dir[0];
    secondary_rayhit.*.ray.dir_y = new_dir[1];
    secondary_rayhit.*.ray.dir_z = new_dir[2];
    secondary_rayhit.*.ray.tnear = 0;
    secondary_rayhit.*.ray.mask = 1;
    secondary_rayhit.*.ray.tfar = std.math.inf(f32);
    secondary_rayhit.*.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;
}
