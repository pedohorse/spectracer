const Color = @import("data_types.zig").Color;
const std = @import("std");
const freq_to_color = @import("spec.zig").spec; // this is CIE XYZ curves

const spec_size = 42;
const freq_strip_width: f32 = 10; // 10 Thz
pub const Spectrum = struct {
    pub const zero: Spectrum = new_black();
    pub const one: Spectrum = new_uniform(1.0);
    pub const white: Spectrum = blk: {
        @setEvalBranchQuota(125 * 42 * 3 * 2);
        break :blk Spectrum.from_color(.{ .r = 1.0, .g = 1.0, .b = 1.0 });
    };

    const color_scale: f32 = freq_strip_width / 100.0; // 100 is some arbitrary scale factor
    pub const start_freq = 380;
    pub const end_freq = 800; // one after last, as usual
    pub const freq_step = 10;
    values: [spec_size]f32,

    pub fn new_black() Spectrum {
        return new_uniform(0.0);
    }

    pub fn new_one() Spectrum {
        return new_uniform(1.0);
    }

    pub fn new_uniform(val: f32) Spectrum {
        var spec = Spectrum{ .values = undefined };
        for (0..spec_size) |i| {
            spec.values[i] = val;
        }
        return spec;
    }

    pub fn sample_at(self: *const Spectrum, frequency: f32) f32 {
        if (frequency > end_freq) return 0;
        if (frequency < start_freq) return 0;
        const i: usize = @intFromFloat(@round((frequency - start_freq) / freq_step)); // no interpolation for now (no point)
        return self.values[i]; // i SHOULD be in range
        // const fi = @floor((frequency - start_freq) / freq_step);
        // const i: usize = @intFromFloat(fi);
        // const t: f32 = @mod(fi, 1.0);
        // return self.values[i] * (1 - t) + self.values[i + 1] * t;
    }

    pub fn set_const(this: *Spectrum, val: f32) void {
        for (&this.values) |*x| {
            x.* = val;
        }
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

    pub fn to_color(this: *const Spectrum) Color {
        var col = Color{ .r = 0, .g = 0, .b = 0 };
        for (this.values, freq_to_color) |val, weights| {
            col.r += weights[0] * val * color_scale;
            col.g += weights[1] * val * color_scale;
            col.b += weights[2] * val * color_scale;
        }
        return xyz_to_rgb(col);
    }

    pub fn from_color(color: Color) Spectrum {
        const max_iterations = 125;
        const eps = 0.0001;
        var spec = Spectrum.new_black();
        var xyz = rgb_to_xyz(color);
        for (0..max_iterations) |_| {
            var abs_diff: f32 = 0.0;
            inline for (.{ "r", "g", "b" }, 0..) |comp_name, comp_i| {
                // step 1
                var c: f32 = 0.0;
                for (spec.values, freq_to_color) |val, weights| {
                    c += weights[comp_i] * val * color_scale;
                }
                // step 2
                const diff = @field(xyz, comp_name) - c;
                abs_diff = @max(abs_diff, (if (diff < 0) -diff else diff));
                // step 3
                for (&spec.values, freq_to_color) |*val, weights| {
                    val.* += 0.5 * diff * weights[comp_i];
                }
                // step 4 ?
            }
            if (abs_diff < eps) break;
        }
        return spec;
    }

    pub fn xyz_to_rgb(color: Color) Color {
        const x = color.r;
        const y = color.g;
        const z = color.b;
        return .{
            .r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            .g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            .b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z,
        };
    }

    pub fn rgb_to_xyz(color: Color) Color {
        const r = color.r;
        const g = color.g;
        const b = color.b;
        return .{
            .r = 0.4124564 * r + 0.3575760 * g + 0.1804374 * b,
            .g = 0.2126728 * r + 0.7151521 * g + 0.0721749 * b,
            .b = 0.0193339 * r + 0.1191920 * g + 0.9503040 * b,
        };
    }
};

test "rgb to xyz to rgb" {
    const clr1: Color = .{ .r = 0.23, .g = 0.45, .b = 0.67 };
    const clr1_act = Spectrum.xyz_to_rgb(Spectrum.rgb_to_xyz(clr1));

    try std.testing.expectApproxEqAbs(clr1.r, clr1_act.r, 0.001);
    try std.testing.expectApproxEqAbs(clr1.g, clr1_act.g, 0.001);
    try std.testing.expectApproxEqAbs(clr1.b, clr1_act.b, 0.001);
}

test "col to spec to col" {
    const clr1: Color = .{ .r = 0.23, .g = 0.45, .b = 0.67 };
    const clr1_act = (Spectrum.from_color(clr1)).to_color();

    try std.testing.expectApproxEqAbs(clr1.r, clr1_act.r, 0.001);
    try std.testing.expectApproxEqAbs(clr1.g, clr1_act.g, 0.001);
    try std.testing.expectApproxEqAbs(clr1.b, clr1_act.b, 0.001);
}
