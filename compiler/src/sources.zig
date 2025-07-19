// SPDX-License-Identifier: MIT

const std = @import("std");

const EIGHT_MEGABYTES = 1 << 23;

pub const SourceFile = struct {
    name: std.ArrayList(u8),
    content: std.ArrayList(u8),
    line_starts: std.ArrayList(u32),

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        name: std.ArrayList(u8),
        content: std.ArrayList(u8),
    ) Self {
        var line_starts = std.ArrayList(usize).init(allocator);
        var line_start_incoming = true;
        for (0.., content.items) |i, c| {
            if (line_start_incoming) {
                line_starts.append(i);
                line_start_incoming = false;
            }
            if (c == '\n') {
                line_start_incoming = true;
            }
        }
        return Self{
            .name = name,
            .content = content,
            .line_starts = line_starts,
        };
    }

    pub fn deinit(self: Self) void {
        self.name.deinit();
        self.content.deinit();
        self.line_starts.deinit();
    }

    pub fn parse_from_file(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{});
        var buffered_reader = std.io.bufferedReader(file.reader());
        const reader = buffered_reader.reader();

        var content_buffer = std.ArrayList(u8).init(allocator);
        try reader.readAllArrayList(&content_buffer, EIGHT_MEGABYTES);

        var file_name = std.ArrayList(u8).init(allocator);
        try file_name.appendSlice(path);

        return init(allocator, file_name, content_buffer);
    }

    pub fn get_line_count(self: *const Self) usize {
        return self.line_starts.items.len;
    }

    /// Get line content for a 1-index line number
    pub fn get_line(self: *const Self, line_num: usize) ?[]const u8 {
        if (line_num == 0 or line_num > self.get_line_count()) {
            return null;
        }
        const line_index = line_num - 1;
        const start = self.line_starts[line_index];
        const end = if (line_num == self.get_line_count()) self.content.items.len else self.line_starts[line_index + 1];
        return self.content[start..end];
    }
};
