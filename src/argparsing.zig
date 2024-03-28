const std = @import("std");
const RenderOptions = @import("data_types.zig").RenderOptions;

pub const ArgsParsingError = error{
    ohNooo,
    printUsage,
};

const ArgsParsingState = enum {
    doneReading,
    readScene,
    readOutput,
    readResolutionX,
    readResolutionY,
    readChunkSize,
    readPrimarySamples,
    readSecondartSamples,
    ReadMaxBounce,
};

fn print_usage() void {
    std.log.info(
        \\
        \\usage: spectracer [flags] [scene_path] [output_path]
        \\
        \\    flags:
        \\      -r WIDTH HEIGHT: set resolution to WIDTH HEIGHT
        \\      -1 count       : set primary sample count
        \\      -2 count       : set secondary ray count
        \\      -d depth       : set maximum ray depth
        \\      -c count       : set render chunk size
        \\      -h             : pring help message
        \\
        \\    scene_path: path to scene, relative to cwd
        \\    output_path: path to png output image, relative to cwd
        \\
    , .{});
}

pub fn parse_args(alloc: std.mem.Allocator) !RenderOptions {
    var options = try RenderOptions.init(alloc);
    var args_iterator = try std.process.argsWithAllocator(alloc);
    defer args_iterator.deinit();

    if (!args_iterator.skip()) {
        std.log.err("no args set for the process? strange", .{});
        return ArgsParsingError.ohNooo;
    }

    var state = ArgsParsingState.readScene;
    var main_state: ArgsParsingState = undefined;
    while (args_iterator.next()) |arg| {
        switch (state) {
            .doneReading => {
                std.log.err("arguments found after output, not supposed to happen!", .{});
                print_usage();
                return ArgsParsingError.ohNooo;
            },
            .readScene, .readOutput => {
                if (arg[0] != '-') { // not a flag
                    if (state == .readScene) {
                        try options.set_scene_path(arg);
                        state = .readOutput;
                    } else if (state == .readOutput) {
                        try options.set_output_path(arg);
                        state = .doneReading;
                    } else unreachable;
                } else {
                    // it's a flag
                    if (arg.len != 2) {
                        std.log.err("flag must be a single letter, but '{s}' found", .{arg});
                        print_usage();
                        return ArgsParsingError.ohNooo;
                    }
                    main_state = state;

                    switch (arg[1]) {
                        'r' => {
                            // resolution
                            state = .readResolutionX;
                        },
                        'c' => {
                            // chunk size
                            state = .readChunkSize;
                        },
                        '1' => {
                            // primary samples
                            state = .readPrimarySamples;
                        },
                        '2' => {
                            // secondary samples
                            state = .readSecondartSamples;
                        },
                        'd' => {
                            // max depth
                            state = .ReadMaxBounce;
                        },
                        'h' => {
                            print_usage();
                            return ArgsParsingError.printUsage;
                        },
                        else => {
                            std.log.err("unknown flag '{s}'", .{arg});
                            print_usage();
                            return ArgsParsingError.ohNooo;
                        },
                    }
                }
            },
            .readResolutionX => {
                state = .readResolutionY;
                options.resolution[0] = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer resolution", .{arg});
                    return ArgsParsingError.ohNooo;
                };
            },
            .readResolutionY => {
                state = main_state;
                options.resolution[1] = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer resolution", .{arg});
                    return ArgsParsingError.ohNooo;
                };
            },
            .readChunkSize => {
                state = main_state;
                options.chunk = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer chunk size", .{arg});
                    return ArgsParsingError.ohNooo;
                };
                if (options.chunk == 0) {
                    std.log.err("chunk size must be greater than zero", .{});
                    return ArgsParsingError.ohNooo;
                }
            },
            .readPrimarySamples => {
                state = main_state;
                options.ray_primary_samples = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer sample count", .{arg});
                    return ArgsParsingError.ohNooo;
                };
                if (options.ray_primary_samples == 0) {
                    std.log.err("sample count must be greater than zero", .{});
                    return ArgsParsingError.ohNooo;
                }
            },
            .readSecondartSamples => {
                state = main_state;
                options.ray_secondary_samples = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer sample count", .{arg});
                    return ArgsParsingError.ohNooo;
                };
                if (options.ray_secondary_samples == 0) {
                    std.log.err("sample count must be greater than zero", .{});
                    return ArgsParsingError.ohNooo;
                }
            },
            .ReadMaxBounce => {
                state = main_state;
                options.ray_max_depth = std.fmt.parseInt(usize, arg, 10) catch {
                    std.log.err("'{s}' does not look like a positive integer max depth value", .{arg});
                    return ArgsParsingError.ohNooo;
                };
            },
        }
    }

    return options;
}
