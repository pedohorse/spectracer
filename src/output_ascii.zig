const std = @import("std");
const Color = @import("data_types.zig").Color;

pub fn preview_ascii(pixels: []Color, width: usize, height: usize) void {
    var stdout = std.io.getStdOut();
    write_ascii(pixels, width, height, stdout.writer()) catch {}; // ignore errors
}

pub fn save_ascii(pixels: []Color, width: usize, height: usize, file_path: []const u8) !void {
    var f = std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => try std.fs.cwd().createFile(file_path, .{}),
        else => return err,
    };
    defer f.close();
    var bufff = std.io.bufferedWriter(f.writer());
    try write_ascii(pixels, width, height, bufff.writer());
}

pub fn write_ascii(pixels: []Color, width: usize, height: usize, output_writer: anytype) !void {
    // sorta preview
    for (0..height) |h| {
        for (0..width) |w| {
            const clr = pixels[h * width + w].r;
            const c: u8 = if (clr < 0.0001) ' ' else if (clr < 0.2) '.' else if (clr < 0.4) '-' else if (clr < 0.6) 'x' else if (clr < 0.8) 'O' else if (clr < 1.0) '0' else '8';
            try output_writer.writeByte(c);
            //print("{c}", .{c});
        }
        try output_writer.writeByte('\n');
        //print("\n", .{});
    }
}
