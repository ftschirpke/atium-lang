const std = @import("std");

const MAX_SIZES = 64;

fn TaggedUnionList(comptime T: type) type {
    const metadata = md: switch (@typeInfo(T)) {
        .@"union" => |u| {
            var unique_sizes_count = 0;
            var unique_sizes = [_]u16{0} ** MAX_SIZES;
            var size_index_for_field = [_]u8{0} ** u.fields.len;
            for (0.., u.fields) |field_index, union_field| {
                var size = @typeInfo(union_field.type);
                const misalignment = size % union_field.alignment;
                if (misalignment != 0) {
                    size += union_field.alignment - misalignment;
                }

                var unique_size_index = null;
                for (0..unique_sizes_count, unique_sizes) |size_index, existing_size| {
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

    return struct {
        const Self = @This();
    };
}
