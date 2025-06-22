// SPDX-License-Identifier: MIT
const std = @import("std");

const BufferedReader = std.io.BufferedReader(4096, std.io.Reader);

const Scanner = struct {
    file: std.fs.File,
    reader: BufferedReader,
    cur: ?u8,
    next: ?u8,

    const Self = @This();

    fn init(path: *[]const u8) std.fs.File.OpenError!Self {
        const file = try std.fs.openFileAbsolute(path);
        return Self{
            .file = file,
            .reader = .{ .unbuffered_reader = file.reader() },
            .cur = null,
            .next = null,
        };
    }

    fn deinit(self: Self) void {
        self.file.close();
    }
};

const Lexer = struct {
    scanner: Scanner,
    path: *[]const u8,
    line: u64,
    col: u64,

    const Self = @This();

    fn init(path: *[]const u8) std.fs.File.OpenError!Self {
        return Self{
            .scanner = try Scanner.init(path),
            .path = path,
            .line = 1,
            .col = 0,
        };
    }

    fn deinit(self: Self) void {
        self.scanner.deinit();
    }
};
