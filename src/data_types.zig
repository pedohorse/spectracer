const std = @import("std");

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,

    /// convert to sRGB in-place
    pub fn toSrgb(self: *Color) void {
        inline for (.{ "r", "g", "b" }) |comp| {
            var c = @field(self, comp);
            c = @max(0, c);
            if (c < 0.0031308) {
                c = 12.92 * c;
            }
            c = 1.055 * std.math.pow(f32, c, 0.41666) - 0.055;
            @field(self, comp) = c;
        }
    }
};

pub const RenderOptions = struct {
    resolution: [2]usize = .{ 1024, 1024 },
    chunk: usize = 256,
    ray_max_depth: u16 = 2,
    ray_bent_max_depth: u16 = 32, //
    ray_secondary_samples: usize = 9,
    ray_primary_samples: usize = 3,
    output_path: std.ArrayList(u8),
    scene_path: std.ArrayList(u8),

    pub fn init(alloc: std.mem.Allocator) !RenderOptions {
        var opts = RenderOptions{
            .output_path = try std.ArrayList(u8).initCapacity(alloc, 256),
            .scene_path = try std.ArrayList(u8).initCapacity(alloc, 256),
        };
        try opts.output_path.appendSlice("outpic.png");
        try opts.scene_path.appendSlice("scene");
        return opts;
    }

    pub fn set_output_path(self: *@This(), path: []const u8) !void {
        self.output_path.clearRetainingCapacity();
        try self.output_path.appendSlice(path);
    }

    pub fn set_scene_path(self: *@This(), path: []const u8) !void {
        self.scene_path.clearRetainingCapacity();
        try self.scene_path.appendSlice(path);
    }

    pub fn deinit(self: *@This()) void {
        self.output_path.deinit();
        self.scene_path.deinit();
    }

    pub fn print_to_log(self: *const @This()) void {
        std.log.info(
            \\Render Options:
            \\  resolution:        {}x{}
            \\  chunk size:        {}
            \\  ray max depth:     {}
            \\  primary samples:   {}
            \\  secondary samples: {}
            \\  output path:       {s}
            \\  scene path:        {s}
        , .{
            self.resolution[0],
            self.resolution[1],
            self.chunk,
            self.ray_max_depth,
            self.ray_primary_samples,
            self.ray_secondary_samples,
            self.output_path.items,
            self.scene_path.items,
        });
    }
};

test "defaults RenderOptions" {
    var opts = try RenderOptions.init(std.testing.allocator);
    defer opts.deinit();

    try std.testing.expectEqualStrings("outpic.png", opts.output_path.items);
    try std.testing.expectEqualStrings("scene", opts.scene_path.items);
}
