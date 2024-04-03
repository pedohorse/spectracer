pub const SceneDescription = struct { objects: []ObjDescription };

pub const ObjDescription = struct {
    file: []u8,
    mat: MatDescription,
    tesselation: f32 = 16,
};

pub const MatDescription = union(enum) {
    lambert: LambertMat,
    light: LightMat,
    glass: GlassMat,
    mirror: MirrorMat,
};

pub const LambertMat = struct {
    cr: f32 = 0.75,
    cg: f32 = 0.75,
    cb: f32 = 0.75,
};

pub const GlassMat = struct {
    ior_base: f32 = 1.2,
    ior_shift: f32 = 0.4,
};

pub const LightMat = struct {
    er: f32 = 2,
    eg: f32 = 2,
    eb: f32 = 2,
};

pub const MirrorMat = struct {};
