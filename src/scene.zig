const std = @import("std");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const shaders = @import("shader.zig");
const Color = @import("data_types.zig").Color;

//pub const Material = enum { light, lambert }; // TODO: add a bunch of shit, obviously

pub const Scene = struct {
    embree_scene: embree.RTCScene,
    material_map: std.AutoHashMap(u32, shaders.Shader),
    shaders_lambert: std.ArrayList(*shaders.Lambert),
    shaders_lights: std.ArrayList(*shaders.Light),
    alloc: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        device: embree.RTCDevice,
    ) Scene {
        return Scene{
            .embree_scene = embree.rtcNewScene(device),
            .material_map = std.AutoHashMap(u32, shaders.Shader).init(allocator),
            .shaders_lambert = std.ArrayList(*shaders.Lambert).init(allocator),
            .shaders_lights = std.ArrayList(*shaders.Light).init(allocator),
            .alloc = allocator,
        };
    }

    pub fn commit(self: *Scene) void {
        embree.rtcCommitScene(self.embree_scene);
    }

    pub fn assign_material(self: *Scene, geo_id: u32, mat: shaders.Shader) !void {
        // TODO: check that mat belongs to scene
        try self.material_map.put(geo_id, mat);
    }

    pub fn new_lambert(self: *Scene, color: Color) !shaders.Shader {
        var shader = try self.alloc.create(shaders.Lambert);
        shader.set_block_color(color);
        try self.shaders_lambert.append(shader);
        return shader.shader();
    }

    pub fn new_light(self: *Scene, color: Color) !shaders.Shader {
        var shader = try self.alloc.create(shaders.Light);
        shader.set_emit_color(color);
        try self.shaders_lights.append(shader);
        return shader.shader();
    }

    pub fn deinit(self: *Scene) void {
        for (self.shaders_lambert.items) |shader_ptr| {
            self.alloc.destroy(shader_ptr);
        }
        for (self.shaders_lights.items) |shader_ptr| {
            self.alloc.destroy(shader_ptr);
        }

        self.material_map.deinit();
        defer embree.rtcReleaseScene(self.embree_scene);
    }
};
