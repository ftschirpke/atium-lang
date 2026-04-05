// SPDX-License-Identifier: MIT

const std = @import("std");

const collections = @import("collections.zig");
const errmsg = @import("error_messages.zig");

const RingBuffer = collections.RingBuffer;

pub const World = struct {
    allocator: std.mem.Allocator,
    sources: std.StringHashMap(SourceFile),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .sources = std.StringHashMap(SourceFile).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.sources.deinit();
    }

    pub fn source_file(self: *Self, path: []const u8) error{OutOfMemory}!*SourceFile {
        if (self.sources.getPtr(path)) |file| {
            return file;
        }
        const new_source_file = try SourceFile.init(self, path);
        try self.sources.put(new_source_file.path.items, new_source_file);
        return self.sources.getPtr(path).?;
    }
};

pub const SourceFile = struct {
    world: *World,
    path: std.ArrayList(u8),
    size: usize,
    line_starts: std.ArrayList(usize),

    const Self = @This();

    const Error = error{InvalidLineNumber};

    fn init(
        world: *World,
        path: []const u8,
    ) error{OutOfMemory}!Self {
        var path_list = try std.ArrayList(u8).initCapacity(world.allocator, path.len);
        try path_list.appendSliceBounded(path);
        var line_starts = try std.ArrayList(usize).initCapacity(world.allocator, 10);
        try line_starts.appendBounded(0);
        return Self{
            .world = world,
            .path = path_list,
            .size = 0,
            .line_starts = line_starts,
        };
    }

    fn deinit(self: Self) void {
        self.path.deinit(self.world.allocator);
        self.line_starts.deinit(self.world.allocator);
    }

    fn add_line_start(self: *Self, line_idx: usize, char_idx: usize) void {
        if (self.line_starts.items.len == line_idx) {
            self.line_starts.append(self.world.allocator, char_idx) catch |err| {
                errmsg.error_oom(err);
            };
        }
    }

    pub fn reader(self: *Self) !SourceReader {
        return SourceReader.init(self.world.allocator, self, 0);
    }

    pub fn get_line(self: *Self, line_num: usize) ![]const u8 {
        if (line_num == 0) return Error.InvalidLineNumber;
        var tmp_reader = try SourceReader.init(self.world.allocator, self, line_num - 1);
        defer tmp_reader.deinit();
        return tmp_reader.get_next_line();
    }
};

const NEWLINE = '\n';

pub const SourceReader = struct {
    allocator: std.mem.Allocator,
    source: *SourceFile,
    reader_buffer: []u8,
    reader: std.fs.File.Reader,
    line: ?[]const u8,
    line_num: usize,
    char_idx: usize,

    const Self = @This();

    pub const Error = error{ EndOfFile, ReadError };

    fn init(allocator: std.mem.Allocator, source: *SourceFile, starting_line_idx: usize) !Self {
        const reader_buffer = try allocator.alloc(u8, 4096);
        var new_self = Self{
            .source = source,
            .allocator = allocator,
            .reader_buffer = reader_buffer,
            .reader = undefined,
            .line = "",
            .line_num = 0,
            .char_idx = 0,
        };
        var file = try std.fs.openFileAbsolute(source.path.items, std.fs.File.OpenFlags{ .mode = .read_only });
        new_self.reader = file.reader(reader_buffer);
        source.size = try new_self.reader.getSize();

        if (starting_line_idx == 0) {
            _ = try new_self.get_next_line();
        } else if (starting_line_idx < source.line_starts.items.len) {
            const line_start_char_idx = source.line_starts.items[starting_line_idx];
            new_self.reader.interface.discardAll(line_start_char_idx) catch {
                unreachable;
            };
            new_self.line_num = starting_line_idx;
            _ = try new_self.get_next_line();
        } else {
            const last_recorded_line_idx = source.line_starts.items.len - 1;
            std.debug.assert(starting_line_idx > last_recorded_line_idx);
            const remaining = starting_line_idx - last_recorded_line_idx;

            const line_start_char_idx = source.line_starts.items[last_recorded_line_idx];
            new_self.reader.interface.discardAll(line_start_char_idx) catch {
                unreachable;
            };
            new_self.line_num = last_recorded_line_idx;

            for (0..remaining) |_| {
                _ = try new_self.get_next_line();
            }
            _ = try new_self.get_next_line();
        }

        return new_self;
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.reader_buffer);
        self.reader.file.close();
    }

    pub fn get_next_line(self: *Self) Error![]const u8 {
        const cur_line = self.line orelse return Error.EndOfFile;

        const next_line = self.reader.interface.takeDelimiterInclusive(NEWLINE) catch |err| switch (err) {
            std.io.Reader.DelimiterError.EndOfStream => self.reader.interface.takeDelimiterExclusive(NEWLINE) catch null,
            else => return Error.ReadError,
        };

        self.line = next_line;
        const line_idx = self.line_num;
        self.line_num += 1;
        self.char_idx += cur_line.len;
        self.source.add_line_start(line_idx, self.char_idx);
        return cur_line;
    }
};
