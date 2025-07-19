// SPDX-License-Identifier: MIT
const std = @import("std");

const SourceFile = @import("sources.zig").SourceFile;

pub const ErrorLevel = enum {
    Error,
    Warning,
    Info,
};

pub fn print_error(
    level: ErrorLevel,
    source: *const SourceFile,
    line_number: u32,
    column: u32,
    highlight_len: usize,
    comptime err_fmt: []const u8,
    err_args: anytype,
    comptime hint_fmt: ?[]const u8,
    hint_args: anytype,
) void {
    const stderr_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr_file);
    const stderr = bw.writer();

    const attempts = 5;
    for (0..attempts) |_| {
        generic_print_error(
            stderr,
            level,
            source,
            line_number,
            column,
            highlight_len,
            err_fmt,
            err_args,
            hint_fmt,
            hint_args,
        ) catch {
            continue;
        };
        break;
    }
    for (0..attempts) |_| {
        bw.flush() catch {
            continue;
        };
        break;
    }
}

fn generic_print_error(
    writer: anytype,
    level: ErrorLevel,
    source: *const SourceFile,
    line_number: u32,
    column: u32,
    highlight_len: usize,
    comptime err_fmt: []const u8,
    err_args: anytype,
    comptime hint_fmt: ?[]const u8,
    hint_args: anytype,
) !void {
    const line_buf_opt = source.get_line(line_number);
    std.debug.assert(line_buf_opt != null);
    const line_buf = line_buf_opt.?;

    var digit_count: u32 = 0;
    var line_remainder = line_number;
    while (line_remainder != 0) {
        line_remainder /= 10;
        digit_count += 1;
    }

    for (0..digit_count + 2) |_| {
        try writer.writeByte('-');
    }
    try writer.print("# {s}:{}:{} - ", .{ source.name.items, line_number, column });

    // TODO: improve usage of error level e.g. with the use of colors
    switch (level) {
        ErrorLevel.Error => try writer.print("ERROR", .{}),
        ErrorLevel.Warning => try writer.print("WARNING", .{}),
        ErrorLevel.Info => try writer.print("INFO", .{}),
    }

    try writer.writeByte(' ');
    try writer.print(err_fmt, err_args);
    try writer.writeByte('\n');

    for (0..digit_count + 2) |_| {
        try writer.writeByte(' ');
    }
    try writer.writeByte('|');
    try writer.writeByte('\n');

    try writer.print(" {} | {s}", .{ line_number, line_buf });

    for (0..digit_count + 2) |_| {
        try writer.writeByte(' ');
    }
    try writer.writeByte('|');

    std.debug.assert(column > 0);

    for (0..column) |_| {
        try writer.writeByte(' ');
    }
    for (0..highlight_len) |_| {
        try writer.writeByte('^');
    }
    try writer.writeByte('\n');

    if (hint_fmt) |hint_format| {
        for (0..digit_count + 2) |_| {
            try writer.writeByte(' ');
        }
        try writer.writeByte('|');
        try writer.writeByte(' ');
        _ = try writer.write("hint: ");
        try writer.print(hint_format, hint_args);
        try writer.writeByte('\n');
    }

    for (0..digit_count + 2) |_| {
        try writer.writeByte(' ');
    }
    try writer.writeByte('|');
    try writer.writeByte('\n');
}
