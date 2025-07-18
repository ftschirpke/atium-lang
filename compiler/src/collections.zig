// SPDX-License-Identifier: MPL-2.0

// the following implementation of a dense data structure for dense unions is inspired by
// a blog post by Adrian Alic (https://alic.dev/blog/dense-enums)
// and his prototype implementation at https://github.com/dist1ll/osmium/blob/main/src/osmium.zig
// and is subject to the terms of the Mozilla Public License v2.0

const std = @import("std");

const MAX_SIZES = 64;

pub fn TaggedUnionList(comptime T: type) type {
    const Tag = std.meta.Tag(T);

    const tag_values = std.enums.values(Tag);
    for (0.., tag_values) |i, tag_value| {
        if (i != @intFromEnum(tag_value)) {
            @compileError("Tagged unions where tagging enum has custom values is not supported");
        }
    }

    const metadata = md: switch (@typeInfo(T)) {
        .@"union" => |u| {
            var max_unique_size = 0;
            var unique_sizes_count = 0;
            var unique_sizes = [_]u16{0} ** MAX_SIZES;
            var size_index_for_field = [_]u8{0} ** u.fields.len;
            for (0.., u.fields) |field_index, union_field| {
                var size = @sizeOf(union_field.type);
                const misalignment = size % union_field.alignment;
                if (misalignment != 0) {
                    size += union_field.alignment - misalignment;
                }

                if (size > max_unique_size) {
                    max_unique_size = size;
                }

                var unique_size_index: ?comptime_int = null;
                for (0..unique_sizes_count) |size_index| {
                    const existing_size = unique_sizes[size_index];
                    if (size == existing_size) {
                        unique_size_index = size_index;
                        break;
                    }
                }
                if (unique_size_index == null) {
                    if (unique_sizes_count >= MAX_SIZES) {
                        @compileError("Union has fields of too many different sizes");
                    }
                    unique_sizes[unique_sizes_count] = size;
                    unique_size_index = unique_sizes_count;
                    unique_sizes_count += 1;
                }
                size_index_for_field[field_index] = unique_size_index.?;
            }

            break :md .{
                .max_unique_size = max_unique_size,
                .unique_sizes_count = unique_sizes_count,
                .unique_sizes = unique_sizes,
                .size_index_for_field = size_index_for_field,
            };
        },
        else => @compileError("Only unions allowed as inner type."),
    };

    const tag_names = std.meta.fieldNames(Tag);

    return struct {
        allocator: std.mem.Allocator,
        data: [metadata.unique_sizes_count]std.ArrayList(u8),

        const Self = @This();

        pub const Index = struct {
            tag: Tag,
            index: usize,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            var array_lists: [metadata.unique_sizes_count]std.ArrayList(u8) = undefined;
            for (0..metadata.unique_sizes_count) |i| {
                array_lists[i] = std.ArrayList(u8).init(allocator);
            }
            return Self{ .allocator = allocator, .data = array_lists };
        }

        pub fn deinit(self: Self) void {
            for (self.data) |array_list| {
                array_list.deinit();
            }
        }

        pub fn append(self: *Self, item: T) !Index {
            const item_tag = std.meta.activeTag(item);
            switch (item_tag) {
                inline else => |tag| {
                    const outer_idx: usize = comptime @intFromEnum(tag);

                    const size_idx = comptime metadata.size_index_for_field[outer_idx];
                    const size = comptime metadata.unique_sizes[size_idx];
                    const raw_item: [size]u8 = std.mem.toBytes(@field(item, tag_names[outer_idx]));

                    const insert_index = self.data[outer_idx].items.len / size;
                    try self.data[outer_idx].appendSlice(&raw_item);

                    return Index{ .tag = tag, .index = insert_index };
                },
            }
        }

        pub fn get(self: *Self, index: Index) T {
            switch (index.tag) {
                inline else => |tag| {
                    const outer_idx: usize = comptime @intFromEnum(tag);
                    const size_idx = comptime metadata.size_index_for_field[outer_idx];
                    const size = comptime metadata.unique_sizes[size_idx];

                    const raw_item_data = self.data[outer_idx].items[size * index.index .. size * (index.index + 1)];
                    var raw_item = [_]u8{0} ** size;
                    @memcpy(&raw_item, raw_item_data);

                    const item = std.mem.bytesAsValue(std.meta.TagPayload(T, tag), &raw_item);
                    return @unionInit(T, tag_names[outer_idx], item.*);
                },
            }
        }

        pub fn memory_footprint(self: *Self) struct { this: usize, naive: usize } {
            var this_footprint: usize = 0;
            var item_count: usize = 0;
            for (self.data, metadata.size_index_for_field) |arr, size_idx| {
                const size = metadata.unique_sizes[size_idx];
                this_footprint += arr.items.len;
                item_count += arr.items.len / size;
            }
            const naive_footprint = item_count * metadata.max_unique_size;
            return .{ .this = this_footprint, .naive = naive_footprint };
        }
    };
}

test "add and retrieve elements" {
    const inner = struct {
        a: u64,
        b: u64,
    };
    const Union = union(enum) {
        small: u16,
        big: inner,
    };
    const Tag = std.meta.Tag(Union);
    const List = TaggedUnionList(Union);

    const small_size = @sizeOf(u16);
    const big_size = @sizeOf(inner);

    var list = List.init(std.testing.allocator);
    defer list.deinit();

    const test_elem1 = Union{ .small = 42 };
    const test_elem2 = Union{ .big = .{ .a = 4, .b = 3 } };
    const test_elem3 = Union{ .big = .{ .a = 123, .b = 456 } };
    const test_elem4 = Union{ .small = 987 };

    const idx1 = try list.append(test_elem1);
    const mem1 = list.memory_footprint();
    try std.testing.expectEqual(mem1.this, small_size);
    try std.testing.expectEqual(mem1.naive, big_size);

    const idx2 = try list.append(test_elem2);
    const mem2 = list.memory_footprint();
    try std.testing.expectEqual(mem2.this, small_size + big_size);
    try std.testing.expectEqual(mem2.naive, 2 * big_size);

    const idx3 = try list.append(test_elem3);
    const mem3 = list.memory_footprint();
    try std.testing.expectEqual(mem3.this, small_size + 2 * big_size);
    try std.testing.expectEqual(mem3.naive, 3 * big_size);

    const idx4 = try list.append(test_elem4);
    const mem4 = list.memory_footprint();
    try std.testing.expectEqual(mem4.this, 2 * small_size + 2 * big_size);
    try std.testing.expectEqual(mem4.naive, 4 * big_size);

    const get1 = list.get(idx1);
    try std.testing.expectEqual(std.meta.activeTag(get1), @field(Tag, "small"));
    try std.testing.expectEqual(get1.small, 42);

    const get2 = list.get(idx2);
    try std.testing.expectEqual(std.meta.activeTag(get2), @field(Tag, "big"));
    try std.testing.expectEqual(get2.big, inner{ .a = 4, .b = 3 });

    const get3 = list.get(idx3);
    try std.testing.expectEqual(std.meta.activeTag(get3), @field(Tag, "big"));
    try std.testing.expectEqual(get3.big, inner{ .a = 123, .b = 456 });

    const get4 = list.get(idx4);
    try std.testing.expectEqual(std.meta.activeTag(get4), @field(Tag, "small"));
    try std.testing.expectEqual(get4.small, 987);
}
