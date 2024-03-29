const std = @import("std");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});
const shaders = @import("shader.zig");
const Color = @import("data_types.zig").Color;

const Material = union(enum) {
    lambert: *shaders.Lambert,
    light: *shaders.Light,
    refract: *shaders.Refract,
    reflect: *shaders.Reflect,
};

pub const Scene = struct {
    embree_scene: embree.RTCScene,
    material_map: std.AutoHashMap(u32, shaders.Shader),
    materials: std.ArrayList(Material),
    alloc: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        device: embree.RTCDevice,
    ) Scene {
        return Scene{
            .embree_scene = embree.rtcNewScene(device),
            .material_map = std.AutoHashMap(u32, shaders.Shader).init(allocator),
            .materials = std.ArrayList(Material).init(allocator),
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
        var material = try self.alloc.create(shaders.Lambert);
        material.set_block_color(color);
        try self.materials.append(Material{ .lambert = material });
        return material.shader();
    }

    pub fn new_light(self: *Scene, color: Color) !shaders.Shader {
        var material = try self.alloc.create(shaders.Light);
        material.set_emit_color(color);
        try self.materials.append(Material{ .light = material });
        return material.shader();
    }

    pub fn new_refract(self: *Scene, ior_base: f32, ior_shift: f32) !shaders.Shader {
        var material = try self.alloc.create(shaders.Refract);
        material.set_ior(ior_base, ior_shift);
        try self.materials.append(Material{ .refract = material });
        return material.shader();
    }

    pub fn new_reflect(self: *Scene) !shaders.Shader {
        var material = try self.alloc.create(shaders.Reflect);
        try self.materials.append(Material{ .reflect = material });
        return material.shader();
    }

    pub fn deinit(self: *Scene) void {
        for (self.materials.items) |mat| {
            switch (mat) {
                .lambert => |material_ptr| self.alloc.destroy(material_ptr),
                .light => |material_ptr| self.alloc.destroy(material_ptr),
                .refract => |material_ptr| self.alloc.destroy(material_ptr),
                .reflect => |material_ptr| self.alloc.destroy(material_ptr),
            }
        }

        self.material_map.deinit();
        defer embree.rtcReleaseScene(self.embree_scene);
    }
};
