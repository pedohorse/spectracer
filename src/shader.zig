const std = @import("std");
const Color = @import("data_types.zig").Color;
const spect = @import("spectrum.zig");
const random_hemisphere = @import("random.zig").random_hemisphere;

pub fn ShaderGenericHmmm(comptime sampler_data_type: ?type) type {
    return struct {
        is_frequency_dependent: bool,
        _dir_sampler: if (sampler_data_type) |t|
            *fn (sampler_data: ?t, f32, f32, @Vector(3, f32), @Vector(3, f32), f32) @Vector(3, f32)
        else
            *fn (f32, f32, @Vector(3, f32), @Vector(3, f32), f32) @Vector(3, f32),
        _sampler_data: if (sampler_data_type) |t| *t else void,

        pub inline fn sample_direction(self: *Shader, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
            if (sampler_data_type)
                return self._dir_sampler(@as(sampler_data_type, @ptrCast(self._sampler_data)), u, v, in, normal, freq)
            else
                return self._dir_sampler(u, v, in, normal, freq);
        }
    };
}

pub const Shader = struct {
    is_light: bool, // TODO: need more generic: emit-only or (spectrum) block-only material
    is_frequency_dependent: bool = false,
    is_non_random_dir: bool = false,

    emit_spectrum: *const spect.Spectrum, // TODO: these must be function sfrom normal angle or smth

    _dir_sampler: *const fn (sampler_data: ?*anyopaque, f32, f32, @Vector(3, f32), @Vector(3, f32), f32) @Vector(3, f32),
    _brdf_sampler_spec: *const fn (sampler_data: ?*anyopaque, @Vector(3, f32), @Vector(3, f32), @Vector(3, f32)) spect.Spectrum,
    _brdf_sampler_freq: *const fn (sampler_data: ?*anyopaque, @Vector(3, f32), @Vector(3, f32), @Vector(3, f32), f32) f32,
    _sampler_data: ?*anyopaque,

    pub inline fn sample_direction(self: *const Shader, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        return self._dir_sampler(self._sampler_data, u, v, in, normal, freq);
    }

    pub inline fn brdf_spec(self: *const Shader, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32)) spect.Spectrum {
        return self._brdf_sampler_spec(self._sampler_data, in, out, normal);
    }

    pub inline fn brdf_freq(self: *const Shader, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) f32 {
        return self._brdf_sampler_freq(self._sampler_data, in, out, normal, freq);
    }
};

pub const Lambert = struct {
    block_spectrum: spect.Spectrum = spect.Spectrum.new_black(),
    emit_spectrum: spect.Spectrum = spect.Spectrum.new_black(),
    // TODO: color need to be stored as spectrum and used

    pub fn set_block_color(self: *Lambert, color: Color) void {
        self.block_spectrum = spect.Spectrum.from_color(color);
        // normalize spectrum's block amount to "white"
        // cuz white is NOT the same as spectrum 1
        for (&self.block_spectrum.values, spect.Spectrum.white.values) |*f, w| {
            f.* = @max(0.0, @min(1.0, f.* / w));
        }
        self.block_spectrum.scale(1.0 / std.math.pi); // energy conservation factor baked in, not to multiply every time
    }

    fn inner_dir_sample(data: ?*anyopaque, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        _ = data;
        _ = in;
        _ = freq;
        return random_hemisphere(u, v, normal);
    }

    fn inner_brdf_spec(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32)) spect.Spectrum {
        _ = in;
        _ = out;
        _ = normal;
        const self: *Lambert = @ptrCast(@alignCast(data.?));
        return self.block_spectrum;
    }

    fn inner_brdf_freq(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) f32 {
        _ = in;
        _ = out;
        _ = normal;
        const self: *Lambert = @ptrCast(@alignCast(data.?));
        return self.block_spectrum.sample_at(freq);
    }

    pub fn shader(self: *Lambert) Shader {
        return Shader{
            .is_light = false,
            .is_frequency_dependent = false,
            .emit_spectrum = &self.emit_spectrum,
            ._dir_sampler = &@This().inner_dir_sample,
            ._brdf_sampler_spec = &@This().inner_brdf_spec,
            ._brdf_sampler_freq = &@This().inner_brdf_freq,
            ._sampler_data = self,
        };
    }
};

pub const Light = struct {
    block_spectrum: spect.Spectrum = spect.Spectrum.new_black(),
    emit_spectrum: spect.Spectrum = spect.Spectrum.new_black(),

    pub fn set_emit_color(self: *Light, color: Color) void {
        self.emit_spectrum = spect.Spectrum.from_color(color);
    }

    fn inner_dir_sample(data: ?*anyopaque, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        _ = data;
        _ = u;
        _ = v;
        _ = in;
        _ = normal;
        _ = freq;
        unreachable;
    }

    fn inner_brdf_spec(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32)) spect.Spectrum {
        _ = data;
        _ = in;
        _ = out;
        _ = normal;
        unreachable;
    }

    fn inner_brdf_freq(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) f32 {
        _ = data;
        _ = in;
        _ = out;
        _ = normal;
        _ = freq;
        unreachable;
    }

    pub fn shader(self: *Light) Shader {
        return Shader{
            .is_light = true,
            .is_frequency_dependent = false,
            .emit_spectrum = &self.emit_spectrum,
            ._dir_sampler = &@This().inner_dir_sample,
            ._brdf_sampler_spec = &@This().inner_brdf_spec,
            ._brdf_sampler_freq = &@This().inner_brdf_freq,
            ._sampler_data = self,
        };
    }
};

pub const Refract = struct {
    ior_base: f32 = 1.2,
    ior_shift: f32 = 0.4,

    pub fn set_ior(self: *Refract, ior_base: f32, ior_shift: f32) void {
        self.ior_base = ior_base;
        self.ior_shift = ior_shift;
    }

    /// all vectors are assumed to be normalized
    fn inner_dir_sample(data: ?*anyopaque, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        _ = u;
        _ = v;

        const self: *Refract = @ptrCast(@alignCast(data.?));

        var n2: f32 = self.ior_base + self.ior_shift * (freq - 380) / 420; // hardcoded for tests
        const dotn = @reduce(.Add, normal * in);
        const r = if (dotn > 0) 1.0 / n2 else n2 / 1.0;
        const dotn2 = dotn * dotn;
        const one_dotn2 = 1.0 / dotn2;
        const costheta22 = one_dotn2 - r * r * (one_dotn2 - 1);
        if (costheta22 <= 0) {
            // means total internal reflection
            return @as(@Vector(3, f32), @splat(2 * dotn)) * normal - in;
        }

        const ret = @as(@Vector(3, f32), @splat(r)) * (-in) +
            @as(@Vector(3, f32), @splat(r * dotn - dotn * @sqrt(costheta22))) * normal;
        //std.debug.print("vv: {}  {}    {} {} {}\n", .{ @reduce(.Add, ret * in), @reduce(.Add, ret * ret), r, dotn, @sqrt(costheta22) });
        return ret;
    }

    fn inner_brdf_spec(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32)) spect.Spectrum {
        _ = in;
        _ = out;
        _ = normal;
        _ = data;

        unreachable; // cuz material is freq-dependent
    }

    fn inner_brdf_freq(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) f32 {
        _ = in;
        _ = data;
        _ = freq;

        return 1.0 / @reduce(.Add, out * normal) / (2 * std.math.pi); // for now just pure refract
    }

    pub fn shader(self: *Refract) Shader {
        return Shader{
            .is_light = false,
            .is_frequency_dependent = true,
            .is_non_random_dir = true,
            .emit_spectrum = &spect.Spectrum.zero,
            ._dir_sampler = &@This().inner_dir_sample,
            ._brdf_sampler_spec = &@This().inner_brdf_spec,
            ._brdf_sampler_freq = &@This().inner_brdf_freq,
            ._sampler_data = self,
        };
    }
};

pub const Reflect = struct {
    fn inner_dir_sample(data: ?*anyopaque, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        // just perfect reflection
        _ = u;
        _ = v;
        _ = data;
        _ = freq;
        const dotn = @reduce(.Add, normal * in);
        return -in + @as(@Vector(3, f32), @splat(2.0 * dotn)) * normal;
    }

    fn inner_brdf_spec(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32)) spect.Spectrum {
        _ = in;
        _ = data;

        var spec = spect.Spectrum.new_one();
        spec.scale(1.0 / @reduce(.Add, out * normal) / (2 * std.math.pi));
        return spec; // for now just pure reflect
    }

    fn inner_brdf_freq(data: ?*anyopaque, in: @Vector(3, f32), out: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) f32 {
        _ = in;
        _ = data;
        _ = freq;

        return 1.0 / @reduce(.Add, out * normal) / (2 * std.math.pi); // for now just pure reflect
    }

    pub fn shader(self: *@This()) Shader {
        return Shader{
            .is_light = false,
            .is_frequency_dependent = false,
            .is_non_random_dir = true,
            .emit_spectrum = &spect.Spectrum.zero,
            ._dir_sampler = &@This().inner_dir_sample,
            ._brdf_sampler_spec = &@This().inner_brdf_spec,
            ._brdf_sampler_freq = &@This().inner_brdf_freq,
            ._sampler_data = self,
        };
    }
};
