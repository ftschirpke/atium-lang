// SPDX-License-Identifier: MIT

const std = @import("std");

pub const SourceFile = struct {
    name: std.ArrayList(u8),
    content: std.ArrayList(u8),
    line_starts: std.ArrayList(usize),

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
