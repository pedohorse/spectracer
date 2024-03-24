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
    is_frequency_dependent: bool,

    emit_spectrum: *spect.Spectrum, // TODO: these must be function sfrom normal angle or smth
    block_spectrum: *spect.Spectrum,

    _dir_sampler: *const fn (sampler_data: ?*anyopaque, f32, f32, @Vector(3, f32), @Vector(3, f32), f32) @Vector(3, f32),
    _sampler_data: ?*anyopaque,

    pub inline fn sample_direction(self: *const Shader, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        return self._dir_sampler(self._sampler_data, u, v, in, normal, freq);
    }
};

pub const Lambert = struct {
    block_spectrum: spect.Spectrum = spect.Spectrum.new_black(),
    emit_spectrum: spect.Spectrum = spect.Spectrum.new_black(),
    // TODO: color need to be stored as spectrum and used

    pub fn set_block_color(self: *Lambert, color: Color) void {
        self.emit_spectrum = spect.Spectrum.from_color(color);
    }

    fn inner_dir_sample(data: ?*anyopaque, u: f32, v: f32, in: @Vector(3, f32), normal: @Vector(3, f32), freq: f32) @Vector(3, f32) {
        _ = data;
        _ = in;
        _ = freq;
        return random_hemisphere(u, v, normal);
    }

    pub fn shader(self: *Lambert) Shader {
        return Shader{
            .is_light = false,
            .is_frequency_dependent = false,
            .emit_spectrum = &self.emit_spectrum,
            .block_spectrum = &self.block_spectrum,
            ._dir_sampler = &@This().inner_dir_sample,
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
        return .{ 0, 0, 0 };
    }

    pub fn shader(self: *Light) Shader {
        return Shader{
            .is_light = true,
            .is_frequency_dependent = false,
            .emit_spectrum = &self.emit_spectrum,
            .block_spectrum = &self.block_spectrum,
            ._dir_sampler = &@This().inner_dir_sample,
            ._sampler_data = self,
        };
    }
};
