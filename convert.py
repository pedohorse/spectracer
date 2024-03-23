
def find_closest_i(sorted_list, val):
    for i, x in enumerate(sorted_list):
        if x > val:
            return i - 1
    return len(sorted_list) - 1


def sample_vals(vals_pairs, sample_pos):
    keys = tuple(x[0] for x in vals_pairs)
    i0 = find_closest_i(keys, sample_pos)
    if i0 == -1 or i0 == len(keys) - 1:
        print('O', sample_pos, i0, vals_pairs[max(0, i0)])
        return vals_pairs[max(0, i0)][1]
    
    key0 = keys[i0]
    key1 = keys[i0 + 1]

    t = (sample_pos - key0) / (key1 - key0)

    return tuple(x*(1-t) + x*t for x in vals_pairs[i0][1])


def do():
    start_l = 380  # nanometers
    end_l = 780
    c = 299_792_458

    l_step = 5
    
    spec_f_points = []
    for i, sample in enumerate(spec_l):
        l = start_l + i * l_step
        spec_f_points.insert(0, (c / l / 1000, sample))  # in teraherz
    
    print(spec_f_points)
    # now need to resample
    start_f = 380
    end_f = 790
    f_step = 10

    spec_f = []
    for freq in range(start_f, end_f + 1, f_step):
        spec_f.append(sample_vals(spec_f_points, freq))

    print(spec_f)
    with open("src/spec.zig", "w") as f:
        f.write(f"// total of {len(spec_f)} samples, from {start_f} to {end_f}, with step {f_step}\n")
        f.write(f"pub const spec: [{len(spec_f)}][3]f32 = .{{\n")
        f.write(",\n".join(f'.{{ {", ".join(str(x) for x in val)} }}' for val in spec_f))
        f.write(" \n};")
        

spec_l = (
        (0.0014,0.0000,0.0065), (0.0022,0.0001,0.0105), (0.0042,0.0001,0.0201),
        (0.0076,0.0002,0.0362), (0.0143,0.0004,0.0679), (0.0232,0.0006,0.1102),
        (0.0435,0.0012,0.2074), (0.0776,0.0022,0.3713), (0.1344,0.0040,0.6456),
        (0.2148,0.0073,1.0391), (0.2839,0.0116,1.3856), (0.3285,0.0168,1.6230),
        (0.3483,0.0230,1.7471), (0.3481,0.0298,1.7826), (0.3362,0.0380,1.7721),
        (0.3187,0.0480,1.7441), (0.2908,0.0600,1.6692), (0.2511,0.0739,1.5281),
        (0.1954,0.0910,1.2876), (0.1421,0.1126,1.0419), (0.0956,0.1390,0.8130),
        (0.0580,0.1693,0.6162), (0.0320,0.2080,0.4652), (0.0147,0.2586,0.3533),
        (0.0049,0.3230,0.2720), (0.0024,0.4073,0.2123), (0.0093,0.5030,0.1582),
        (0.0291,0.6082,0.1117), (0.0633,0.7100,0.0782), (0.1096,0.7932,0.0573),
        (0.1655,0.8620,0.0422), (0.2257,0.9149,0.0298), (0.2904,0.9540,0.0203),
        (0.3597,0.9803,0.0134), (0.4334,0.9950,0.0087), (0.5121,1.0000,0.0057),
        (0.5945,0.9950,0.0039), (0.6784,0.9786,0.0027), (0.7621,0.9520,0.0021),
        (0.8425,0.9154,0.0018), (0.9163,0.8700,0.0017), (0.9786,0.8163,0.0014),
        (1.0263,0.7570,0.0011), (1.0567,0.6949,0.0010), (1.0622,0.6310,0.0008),
        (1.0456,0.5668,0.0006), (1.0026,0.5030,0.0003), (0.9384,0.4412,0.0002),
        (0.8544,0.3810,0.0002), (0.7514,0.3210,0.0001), (0.6424,0.2650,0.0000),
        (0.5419,0.2170,0.0000), (0.4479,0.1750,0.0000), (0.3608,0.1382,0.0000),
        (0.2835,0.1070,0.0000), (0.2187,0.0816,0.0000), (0.1649,0.0610,0.0000),
        (0.1212,0.0446,0.0000), (0.0874,0.0320,0.0000), (0.0636,0.0232,0.0000),
        (0.0468,0.0170,0.0000), (0.0329,0.0119,0.0000), (0.0227,0.0082,0.0000),
        (0.0158,0.0057,0.0000), (0.0114,0.0041,0.0000), (0.0081,0.0029,0.0000),
        (0.0058,0.0021,0.0000), (0.0041,0.0015,0.0000), (0.0029,0.0010,0.0000),
        (0.0020,0.0007,0.0000), (0.0014,0.0005,0.0000), (0.0010,0.0004,0.0000),
        (0.0007,0.0002,0.0000), (0.0005,0.0002,0.0000), (0.0003,0.0001,0.0000),
        (0.0002,0.0001,0.0000), (0.0002,0.0001,0.0000), (0.0001,0.0000,0.0000),
        (0.0001,0.0000,0.0000), (0.0001,0.0000,0.0000), (0.0000,0.0000,0.0000)
    )


do()
