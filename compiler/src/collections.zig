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
            var unique_sizes_count = 0;
            var unique_sizes = [_]u16{0} ** MAX_SIZES;
            var size_index_for_field = [_]u8{0} ** u.fields.len;
            for (0.., u.fields) |field_index, union_field| {
                var size = @sizeOf(union_field.type);
                const misalignment = size % union_field.alignment;
                if (misalignment != 0) {
                    size += union_field.alignment - misalignment;
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
                    unique_sizes_count += 1;
                    unique_size_index = unique_sizes_count;
                }
                size_index_for_field[field_index] = unique_size_index.?;
            }

            break :md .{
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

        const Index = struct {
            tag: Tag,
            index: usize,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            var array_lists: [metadata.unique_sizes_count]std.ArrayList(u8) = undefined;
            for (0..metadata.unique_sizes_count) |i| {
                array_lists[i] = std.ArrayList(u8).init();
            }
            return Self{ .allocator = allocator, .data = array_lists };
        }

        pub fn deinit(self: Self) void {
            for (self.data) |array_list| {
                array_list.deinit();
            }
        }

        pub fn append(self: *Self, item: T) !void {
            const tag = std.meta.activeTag(item);
            const outer_idx: usize = @enumFromInt(tag);

            const size = comptime metadata.size_index_for_field[outer_idx];
            const raw_item: [size]u8 = @bitCast(@field(item, tag_names[outer_idx]));

            const insert_index = self.data[outer_idx].items.len / size;
            try self.data[outer_idx].appendSlice(&raw_item);

            return Index{ .tag = tag, .index = insert_index };
        }

        pub fn get(self: *Self, index: Index) !T {
            const outer_idx: usize = @enumFromInt(index.tag);
            const size = comptime metadata.size_index_for_field[outer_idx];

            const raw_item_data = self.data[outer_idx].items[index.index .. index.index + size];
            var raw_item = [_]u8{0} ** size;
            @memcpy(&raw_item, raw_item_data);

            const item: std.meta.TagPayload(T, Tag) = @bitCast(raw_item);
            return @unionInit(T, tag_names, item);
        }
    };
}
