const std = @import("std");
const Color = @import("data_types.zig").Color;
const spng = @cImport({
    @cInclude("spng.h");
});

const alloc = std.heap.page_allocator;

pub fn save_png(pixels: []Color, width: usize, height: usize, file_path: []const u8) !void {
    var f = std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => try std.fs.cwd().createFile(file_path, .{}),
        else => return err,
    };
    defer f.close();
    var bufff = std.io.bufferedWriter(f.writer());
    defer bufff.flush() catch {};
    const btype = @TypeOf(bufff);

    const write_fn = struct {
        fn inner_write_fn(context: ?*spng.spng_ctx, user: ?*anyopaque, data_raw: ?*anyopaque, size: usize) callconv(.C) c_int {
            var buffered_writer: *btype = @as(*btype, @ptrCast(@alignCast(user)));
            _ = context;
            var data: [*]u8 = @ptrCast(@alignCast(data_raw));
            //std.debug.print("{s}", .{data[0..size]});
            buffered_writer.writer().writeAll(data[0..size]) catch {
                std.debug.print("oh no, writing error!\n", .{});
                return 1;
            };
            return 0;
        }
    }.inner_write_fn;

    var context = spng.spng_ctx_new(spng.SPNG_CTX_ENCODER);
    defer spng.spng_ctx_free(context);
    _ = spng.spng_set_png_stream(context, &write_fn, &bufff);
    defer _ = spng.spng_encode_chunks(context);

    var ihdr = spng.spng_ihdr{
        .width = @intCast(width),
        .height = @intCast(height),
        .bit_depth = 8,
        .color_type = 6, // true color + alpha, https://www.w3.org/TR/2003/REC-PNG-20031110/#table111
        .compression_method = 0, // no comp
        .filter_method = 0, // no filter
        .interlace_method = 0, // no interlace
    };

    _ = spng.spng_set_ihdr(context, &ihdr);

    var line_buff = try alloc.alloc(u8, width * 4);
    defer alloc.free(line_buff);

    _ = spng.spng_encode_image(context, null, 0, spng.SPNG_FMT_PNG, spng.SPNG_ENCODE_PROGRESSIVE);
    for (0..height) |y| {
        for (0..width) |x| {
            line_buff[4 * x + 0] = @intFromFloat(@max(0, @min(255, pixels[height * y + x].r * 255)));
            line_buff[4 * x + 1] = @intFromFloat(@max(0, @min(255, pixels[height * y + x].g * 255)));
            line_buff[4 * x + 2] = @intFromFloat(@max(0, @min(255, pixels[height * y + x].b * 255)));
            line_buff[4 * x + 3] = 255;
        }
        _ = spng.spng_encode_row(context, @ptrCast(line_buff), 4 * width);
    }
}
