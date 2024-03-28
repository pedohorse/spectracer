const std = @import("std");
const print = std.debug.print;
const obj_loader = @import("load_obj_geo.zig");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const parse_args = @import("argparsing.zig").parse_args;

const Pool = @import("parallel.zig").Pool;
const Color = @import("data_types.zig").Color;
const Spectrum = @import("spectrum.zig").Spectrum;
const RenderOptions = @import("data_types.zig").RenderOptions;
const Scene = @import("scene.zig").Scene;
const Shader = @import("shader.zig").Shader;

const output_ascii = @import("output_ascii.zig");
const output_png = @import("output_png.zig");

const logging = @import("log.zig");
pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = logging.logFn;
};

const Err = error{
    general,
    argParsingError,
};

const SceneData = struct {
    scene: *Scene,
    focal: f32,
    options: *RenderOptions,
};

const ChunkData = struct {
    scene_data: *SceneData,
    intersection_context: *embree.RTCIntersectContext,
    chunk_start_x: usize,
    chunk_start_y: usize,
    shared_finished_chunks_count: *usize,
};

pub fn main() !void {
    logging.init_logging();
    const alloc: std.mem.Allocator = std.heap.c_allocator;
    std.log.debug("reading command line arguments", .{});

    var render_options: RenderOptions = try parse_args(alloc);
    defer render_options.deinit();

    render_options.print_to_log();

    var device = embree.rtcNewDevice(null);
    defer embree.rtcReleaseDevice(device);
    std.log.debug("loading scene", .{});
    var scene = try obj_loader.load_obj_scene(device, render_options.scene_path.items);
    defer scene.deinit();
    std.log.debug("scene loaded", .{});

    {
        std.log.debug("preparing data", .{});
        const width = render_options.resolution[0];
        const height = render_options.resolution[1];
        var pixels: []Color align(16) = try alloc.alloc(Color, width * height);
        defer alloc.free(pixels);

        var inter_context: embree.RTCIntersectContext align(16) = undefined;
        embree.rtcInitIntersectContext(&inter_context);
        var scene_context = SceneData{
            .scene = &scene,
            .focal = 1.5,
            .options = &render_options,
        };

        var chunks: [][]Color = undefined;
        var chunk_datas: []ChunkData = undefined;
        var finished_chunks_counter: usize = 0;
        {
            const chunk_size = render_options.chunk;
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
                chunk_datas[ci].shared_finished_chunks_count = &finished_chunks_counter;
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

            std.log.debug("converting picture", .{});
            thread_pool.parallel_for([]Color, u8, 0, chunks.len, chunks, null, &convert_to_srgb);
        }

        //output_ascii.preview_ascii(pixels, width, height);
        std.log.debug("saving picture", .{});
        //try output_ascii.save_ascii(pixels, width, height, "outpic.txt");
        try output_png.save_png(pixels, width, height, render_options.output_path.items);
        std.log.debug("done", .{});
    }
}

fn convert_to_srgb(chunks: [][]Color, chunk_id: usize, chunk_datas: ?*u8) void {
    _ = chunk_datas;
    for (chunks[chunk_id]) |*pixel| {
        pixel.toSrgb();
    }
}

fn trace_chunk2(chunks: [][]Color, chunk_id: usize, chunk_datas: ?*[]const ChunkData) void {
    var randomizer = std.rand.Xoshiro256.init(chunk_id + 132435);
    var rayhit: embree.RTCRayHit align(16) = undefined;
    // starting pixel of the chunk
    const chunk_data = chunk_datas.?.*[chunk_id];
    var pix_x = chunk_data.chunk_start_x;
    var pix_y = chunk_data.chunk_start_y;
    const focal = chunk_data.scene_data.focal;
    const focal2 = focal * focal;
    const width = chunk_data.scene_data.options.resolution[0];
    const height = chunk_data.scene_data.options.resolution[1];
    const ortho_width = 0.5;
    const ortho_height = 0.5;
    const primary_samples = chunk_data.scene_data.options.ray_primary_samples;

    for (chunks[chunk_id]) |*pixel| {
        var avg_val: Spectrum = Spectrum.new_black();
        for (0..primary_samples * primary_samples) |sample_i| {
            const xs_offset: f32 = (@as(f32, @floatFromInt(sample_i % primary_samples)) + 0.5) / @as(f32, @floatFromInt(primary_samples)) - 0.5;
            const ys_offset: f32 = (@as(f32, @floatFromInt(sample_i / primary_samples)) + 0.5) / @as(f32, @floatFromInt(primary_samples)) - 0.5;

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
        avg_val.scale(1.0 / @as(f32, @floatFromInt(primary_samples * primary_samples)));
        //pixel.* = .{ .r = avg_val, .g = avg_val, .b = avg_val };
        pixel.* = avg_val.to_color();

        pix_x += 1;
        if (pix_x == width) {
            pix_x = 0;
            pix_y += 1;
        }
    }

    // inc chunkid and maybe print progress
    const finished_chunc_count = @atomicRmw(usize, chunk_data.shared_finished_chunks_count, .Add, 1, .Monotonic);
    const progress = finished_chunc_count * 100 / chunks.len;
    if (finished_chunc_count > 0 and progress / 5 != ((finished_chunc_count - 1) * 100 / chunks.len) / 5) {
        std.log.debug("R: {}%", .{progress});
    }
}

fn trace_ray(comptime T: type, rayhit: *embree.RTCRayHit, frequency: f32, chunk_data: *const ChunkData, rng: std.rand.Random, depth: u32) T {
    if (depth > chunk_data.scene_data.options.ray_max_depth) {
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
        const val = 0.0; //rayhit.ray.dir_y; // imitate sky light
        if (T == Spectrum) {
            return Spectrum.new_uniform(val);
        } else if (T == f32) {
            return val;
        } else unreachable;
    }

    // shading
    var val: T = if (T == Spectrum) Spectrum.new_black() else if (T == f32) 0.0 else unreachable;
    const shader: Shader = chunk_data.scene_data.scene.material_map.get(rayhit.hit.geomID) orelse return val;

    // check if material is emissive only
    if (shader.is_light) {
        //const intens = 10.0; // TODO: take intensity from light properties
        if (T == Spectrum) {
            val = shader.emit_spectrum.*;
        } else if (T == f32) {
            val = shader.emit_spectrum.sample_at(frequency);
        } else unreachable;
        return val;
    }

    var secondary_rayhit: embree.RTCRayHit align(16) = undefined;
    const eps = 0.0001;
    const normal: @Vector(3, f32) = blk: {
        var vec: @Vector(3, f32) = .{ rayhit.hit.Ng_x, rayhit.hit.Ng_y, rayhit.hit.Ng_z };
        vec /= @splat(@sqrt(@reduce(.Add, vec * vec)));
        break :blk vec;
    };
    const ray_in: @Vector(3, f32) = .{ -rayhit.ray.dir_x, -rayhit.ray.dir_y, -rayhit.ray.dir_z }; // traditionally, both in/out vecs are from point
    const ray_hit_point: @Vector(3, f32) = .{
        rayhit.ray.org_x + rayhit.ray.dir_x * rayhit.ray.tfar + eps * normal[0],
        rayhit.ray.org_y + rayhit.ray.dir_y * rayhit.ray.tfar + eps * normal[1],
        rayhit.ray.org_z + rayhit.ray.dir_z * rayhit.ray.tfar + eps * normal[2],
    };

    const sample_count: usize = if (shader.is_non_random_dir) 1 else chunk_data.scene_data.options.ray_secondary_samples;

    for (0..sample_count) |_| {
        if (T == Spectrum) {
            if (shader.is_frequency_dependent) {
                // case when spectrum needs frequency-dependent bsdf sampling
                const ru = rng.float(f32);
                const rv = rng.float(f32);
                for (&val.values, 0..) |*x, i| {
                    const freq: f32 = Spectrum.start_freq + Spectrum.freq_step * @as(f32, @floatFromInt(i));
                    // TODO: generalize ray sampling func
                    const new_dir: @Vector(3, f32) = shader.sample_direction(ru, rv, ray_in, normal, freq);
                    const dotn = @reduce(.Add, new_dir * normal);
                    const hitoffset: @Vector(3, f32) = if (dotn < 0)
                        .{ -2 * eps * normal[0], -2 * eps * normal[1], -2 * eps * normal[2] }
                    else
                        .{ 0, 0, 0 };
                    init_secondary_rayhit(&secondary_rayhit, ray_hit_point + hitoffset, new_dir);

                    const sample = trace_ray(f32, &secondary_rayhit, freq, chunk_data, rng, depth + 1);
                    const brdf = shader.brdf_freq(ray_in, new_dir, normal, freq);
                    x.* += sample * brdf * dotn;
                }
            } else {
                // case when ray does not need frequency-dependent bsdf sampling
                const new_dir: @Vector(3, f32) = shader.sample_direction(rng.float(f32), rng.float(f32), ray_in, normal, 0);
                const dotn = @reduce(.Add, new_dir * normal);
                const hitoffset: @Vector(3, f32) = if (dotn < 0)
                    .{ -2 * eps * normal[0], -2 * eps * normal[1], -2 * eps * normal[2] }
                else
                    .{ 0, 0, 0 };
                init_secondary_rayhit(&secondary_rayhit, ray_hit_point + hitoffset, new_dir);

                const new_sample: T = trace_ray(T, &secondary_rayhit, frequency, chunk_data, rng, depth + 1);
                const brdf_spec = shader.brdf_spec(ray_in, new_dir, normal);
                for (&val.values, new_sample.values, brdf_spec.values) |*x, y, b| {
                    x.* += y * b * dotn;
                }
            }
        } else if (T == f32) {
            // case of single frequency ray sampling
            const new_dir: @Vector(3, f32) = shader.sample_direction(rng.float(f32), rng.float(f32), ray_in, normal, frequency);
            const dotn = @reduce(.Add, new_dir * normal);
            const hitoffset: @Vector(3, f32) = if (dotn < 0)
                .{ -2 * eps * normal[0], -2 * eps * normal[1], -2 * eps * normal[2] }
            else
                .{ 0, 0, 0 };
            init_secondary_rayhit(&secondary_rayhit, ray_hit_point + hitoffset, new_dir);

            const new_sample: T = trace_ray(T, &secondary_rayhit, frequency, chunk_data, rng, depth + 1);
            const brdf = shader.brdf_freq(ray_in, new_dir, normal, frequency);
            val += new_sample * brdf * dotn;
        } else unreachable;
    }

    if (sample_count > 0) {
        // TODO: total weight here is uniform, it's incorrect in general, it should depend on dir distribution
        const total_weight: f32 = 2 * std.math.pi / @as(f32, @floatFromInt(sample_count));
        if (T == Spectrum) {
            val.scale(total_weight);
        } else if (T == f32) {
            val *= total_weight;
        } else unreachable;
    }

    return val;
}

fn init_secondary_rayhit(secondary_rayhit: *embree.RTCRayHit, rayhit_point: @Vector(3, f32), new_dir: @Vector(3, f32)) void {
    secondary_rayhit.*.ray.org_x = rayhit_point[0];
    secondary_rayhit.*.ray.org_y = rayhit_point[1];
    secondary_rayhit.*.ray.org_z = rayhit_point[2];
    secondary_rayhit.*.ray.dir_x = new_dir[0];
    secondary_rayhit.*.ray.dir_y = new_dir[1];
    secondary_rayhit.*.ray.dir_z = new_dir[2];
    secondary_rayhit.*.ray.tnear = 0;
    secondary_rayhit.*.ray.mask = 1;
    secondary_rayhit.*.ray.tfar = std.math.inf(f32);
    secondary_rayhit.*.hit.geomID = embree.RTC_INVALID_GEOMETRY_ID;
}
