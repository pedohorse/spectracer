const std = @import("std");

pub inline fn random_hemisphere(u: f32, v: f32, normal: @Vector(3, f32)) @Vector(3, f32) {
    const sample = random_sphere(u, v);
    return if (@reduce(.Add, sample * normal) < 0)
        -sample
    else
        sample;
}

pub inline fn random_sphere(u: f32, v: f32) @Vector(3, f32) {
    const fi = u * 2 * std.math.pi;
    var x = @cos(fi);
    var y = @sin(fi);
    var z = -1 + 2 * v;
    var cz = @sqrt(1 - z * z);

    return .{ x * cz, y * cz, z };
}

test "random_hemisphere" {
    var randomizer = std.rand.Xoshiro256.init(132435);
    var rng = randomizer.random();
    const ray1 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 1, 0 });
    const ray2 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, -1, 0 });
    const ray3 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 1, 0, 0 });
    const ray4 = random_hemisphere(rng.float(f32), rng.float(f32), .{ -1, 0, 0 });
    const ray5 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 0, 1 });
    const ray6 = random_hemisphere(rng.float(f32), rng.float(f32), .{ 0, 0, -1 });
    try std.testing.expect(ray1[1] >= 0);
    try std.testing.expect(ray2[1] <= 0);
    try std.testing.expect(ray3[0] >= 0);
    try std.testing.expect(ray4[0] <= 0);
    try std.testing.expect(ray5[2] >= 0);
    try std.testing.expect(ray6[2] <= 0);
}
