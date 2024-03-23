const std = @import("std");
const embree = @cImport({
    @cInclude("embree3/rtcore.h");
});

pub const Material = enum { light, lambert }; // TODO: add a bunch of shit, obviously

pub const Scene = struct {
    embree_scene: embree.RTCScene,
    material_map: std.AutoHashMap(u32, Material),

    pub fn deinit(self: *Scene) void {
        self.material_map.deinit();
        defer embree.rtcReleaseScene(self.embree_scene);
    }
};
