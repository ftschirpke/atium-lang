const std = @import("std");

const collections = @import("collections.zig");

const AstItem = union(enum) {};

const List = collections.TaggedUnionList(AstItem);

const Parser = struct {
    list: List,
    top_level: std.ArrayList(List.Index),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const top_level = std.ArrayList(List.Index).init(allocator);
        const list = List.init(allocator);
        return Self{ .top_level = top_level, .list = list };
    }

    pub fn deinit(self: Self) void {
        self.list.deinit();
        self.top_level.deinit();
    }

    // TODO: implent parsing
};
