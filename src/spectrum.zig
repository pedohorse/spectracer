const Color = @import("data_types.zig").Color;
const std = @import("std");
const freq_to_color = @import("spec.zig").spec;

const spec_size = 42;
const freq_strip_width: f32 = 10; // 10 Thz
pub const Spectrum = struct {
    pub const start_freq = 380;
    pub const end_freq = 400; // one after last, as usual
    pub const freq_step = 10;
    values: [spec_size]f32,

    pub fn new_black() Spectrum {
        return new_uniform(0.0);
    }

    pub fn new_white() Spectrum {
        return new_uniform(1.0);
    }

    pub fn new_uniform(val: f32) Spectrum {
        var spec = Spectrum{ .values = undefined };
        for (0..spec_size) |i| {
            spec.values[i] = val;
        }
        return spec;
    }

    pub fn add(this: *Spectrum, other_spec: *const Spectrum) void {
        for (&this.values, other_spec.values) |*x, y| {
            x.* += y;
        }
    }

    pub fn scale(this: *Spectrum, factor: f32) void {
        for (&this.values) |*x| {
            x.* *= factor;
        }
    }

    pub fn to_color(this: *Spectrum) Color {
        const color_scale: f32 = freq_strip_width / 100.0; // 100 is some arbitrary scale factor
        var col = Color{ .r = 0, .g = 0, .b = 0 };
        for (this.values, freq_to_color) |val, weights| {
            col.r += weights[0] * val * color_scale;
            col.g += weights[1] * val * color_scale;
            col.b += weights[2] * val * color_scale;
        }
        return col;
    }
};
