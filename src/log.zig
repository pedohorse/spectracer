const std = @import("std");

var proc_start: i64 = 0;

pub fn init_logging() void {
    proc_start = std.time.microTimestamp();
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // mostly copied default impl
    const level_txt = "[" ++ comptime level.asText() ++ "]";
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const time = @as(u64, @intCast(std.time.microTimestamp() - proc_start));
    nosuspend stderr.print("[{}.{d:0>6}]" ++ level_txt ++ prefix2 ++ format ++ "\n", .{ time / 1000000, time % 1000000 } ++ args) catch return;
}
