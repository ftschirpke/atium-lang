// SPDX-License-Identifier: MPL-2.0

// the following implementation of a dense data structure for dense unions is inspired by
// a blog post by Adrian Alic (https://alic.dev/blog/dense-enums)
// and his prototype implementation at https://github.com/dist1ll/osmium/blob/main/src/osmium.zig
// and is subject to the terms of the Mozilla Public License v2.0

const std = @import("std");

const id = @import("id.zig");

const MAX_SIZES = 32;

pub fn TaggedUnionList(comptime T: type) type {
    const Error = error{OutOfIndexSpace};

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

            const pub_index = id.IdType;
            const element_index_type = u32;
            const priv_index = struct {
                index: element_index_type,
                tag: Tag,
            };
            const idx_split = @bitSizeOf(element_index_type);
            if (@bitSizeOf(Tag) > (@bitSizeOf(pub_index) - idx_split)) {
                @compileError("Union has too many fields to fit into merged union index");
            }
            const max_data_index = std.math.maxInt(element_index_type);

            break :md .{
                .max_unique_size = max_unique_size,
                .max_data_index = max_data_index,
                .unique_sizes_count = unique_sizes_count,
                .unique_sizes = unique_sizes,
                .size_index_for_field = size_index_for_field,
                .public_index = pub_index,
                .private_index = priv_index,
                .index_split_offset = idx_split,
            };
        },
        else => @compileError("Only unions allowed as inner type."),
    };

    const tag_names = std.meta.fieldNames(Tag);

    return struct {
        allocator: std.mem.Allocator,
        data: [metadata.unique_sizes_count]std.ArrayList(u8),

        const Self = @This();

        pub const Index = metadata.public_index;
        const InternalIndex = metadata.private_index;

        fn index_internal_to_primitive(internal: InternalIndex) Index {
            return (@as(Index, @intFromEnum(internal.tag)) << metadata.index_split_offset) + @as(Index, internal.index);
        }

        fn index_primitive_to_internal(primitive: Index) InternalIndex {
            return InternalIndex{
                .index = @truncate(primitive),
                .tag = @enumFromInt(primitive >> metadata.index_split_offset),
            };
        }

        pub fn init(allocator: std.mem.Allocator) !Self {
            var array_lists: [metadata.unique_sizes_count]std.ArrayList(u8) = undefined;
            for (0..metadata.unique_sizes_count) |i| {
                array_lists[i] = try std.ArrayList(u8).initCapacity(allocator, 10);
            }
            return Self{ .allocator = allocator, .data = array_lists };
        }

        pub fn deinit(self: *Self) void {
            for (0..self.data.len) |i| {
                self.data[i].deinit(self.allocator);
            }
        }

        pub fn append(self: *Self, item: T) !Index {
            const item_tag = std.meta.activeTag(item);
            switch (item_tag) {
                inline else => |tag| {
                    const tag_num: usize = comptime @intFromEnum(tag);
                    const outer_idx = comptime metadata.size_index_for_field[tag_num];
                    const size = comptime metadata.unique_sizes[outer_idx];

                    const raw_item: [size]u8 = std.mem.toBytes(@field(item, tag_names[tag_num]));
                    const insert_index = self.data[outer_idx].items.len / size;
                    if (insert_index > metadata.max_data_index) {
                        return Error.OutOfIndexSpace;
                    }
                    try self.data[outer_idx].appendSlice(self.allocator, &raw_item);

                    const internal_index = InternalIndex{ .tag = tag, .index = @truncate(insert_index) };
                    return index_internal_to_primitive(internal_index);
                },
            }
        }

        pub fn get(self: *Self, primitive_index: Index) T {
            const index = index_primitive_to_internal(primitive_index);
            switch (index.tag) {
                inline else => |tag| {
                    const tag_num: usize = comptime @intFromEnum(tag);
                    const outer_idx = comptime metadata.size_index_for_field[tag_num];
                    const size = comptime metadata.unique_sizes[outer_idx];

                    const raw_item_data = self.data[outer_idx].items[size * index.index .. size * (index.index + 1)];
                    var raw_item = [_]u8{0} ** size;
                    @memcpy(&raw_item, raw_item_data);

                    const item = std.mem.bytesAsValue(std.meta.TagPayload(T, tag), &raw_item);
                    return @unionInit(T, tag_names[tag_num], item.*);
                },
            }
        }

        pub fn memory_footprint(self: *Self) struct { this: usize, naive: usize } {
            var this_footprint: usize = 0;
            var item_count: usize = 0;
            for (self.data, 0..metadata.unique_sizes_count) |arr, size_idx| {
                const size = metadata.unique_sizes[size_idx];
                this_footprint += arr.items.len;
                item_count += arr.items.len / size;
            }
            const naive_footprint = item_count * metadata.max_unique_size;
            return .{ .this = this_footprint, .naive = naive_footprint };
        }
    };
}

test "TaggedUnionList - add and retrieve elements" {
    const inner = struct {
        a: u64,
        b: u64,
    };
    const Union = union(enum) {
        small: u16,
        big: inner,
        other_big: u128,
    };
    const Tag = std.meta.Tag(Union);
    const List = TaggedUnionList(Union);

    const small_size = @sizeOf(u16);
    const big_size = @sizeOf(inner);
    std.debug.assert(big_size == @sizeOf(u128));

    var list = try List.init(std.testing.allocator);
    defer list.deinit();

    const test_elem1 = Union{ .small = 42 };
    const test_elem2 = Union{ .big = .{ .a = 4, .b = 3 } };
    const test_elem3 = Union{ .other_big = 123456 };
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
    try std.testing.expectEqual(std.meta.activeTag(get3), @field(Tag, "other_big"));
    try std.testing.expectEqual(get3.other_big, 123456);

    const get4 = list.get(idx4);
    try std.testing.expectEqual(std.meta.activeTag(get4), @field(Tag, "small"));
    try std.testing.expectEqual(get4.small, 987);
}

pub fn RingBuffer(comptime T: type, capacity: comptime_int) type {
    return struct {
        items: [capacity]T,
        cur: usize,
        len: usize,

        const Self = @This();

        const Error = error{ IndexOutOfBounds, TooManyElementsForCapacity, RequestedMoreElementsThanAvailable };

        pub const SplitSlice = struct {
            first: []const T,
            second: ?[]const T,
        };

        pub fn init() Self {
            return Self{
                .items = {},
                .cur = 0,
                .len = 0,
            };
        }

        pub fn initFromSlice(slice: []const T) !Self {
            if (slice.len > capacity) return Error.TooManyElementsForCapacity;
            var self = init();
            for (slice) |item| {
                self.add(item);
            }
            return self;
        }

        fn advance_cur(self: *Self, count: usize) void {
            for (0..count) |_| {
                self.cur += 1;
                if (self.cur == capacity) {
                    self.cur = 0;
                }
            }
        }

        pub fn add(self: *Self, item: T) void {
            if (self.len < capacity) {
                const index = (self.cur + self.len) % capacity;
                self.items[index] = item;
                self.len += 1;
            } else {
                self.items[self.cur] = item;
                self.advance_cur(1);
            }
        }

        fn get(self: *const Self, count: usize) []const T {
            const end = @min(self.cur + count, capacity);
            return self.items[self.cur..end];
        }

        fn peek(self: *const Self, count: usize) Error!SplitSlice {
            if (count > self.len) {
                return Error.RequestedMoreElementsThanAvailable;
            }
            const first = self.get(count);
            const remaining = count - first.len;
            if (remaining == 0) {
                return SplitSlice{
                    .first = first,
                    .second = null,
                };
            } else {
                return SplitSlice{
                    .first = first,
                    .second = self.get(remaining),
                };
            }
        }

        fn consume(self: *Self, count: usize) Error!SplitSlice {
            const split_slice = try peek(count);
            self.advance_cur(count);
            return split_slice;
        }
    };
}
