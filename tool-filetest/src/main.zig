// SPDX-License-Identifier: MIT

const std = @import("std");

const Error = error{ MissingFilePath, InvalidFilePath, CheckFailed, InvalidCheck };

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    var args = std.process.argsWithAllocator(gpa) catch |err| {
        std.log.err("Unexpected problem while allocating memory for process arguments - {}", .{err});
        return;
    };
    defer args.deinit();

    std.debug.assert(args.skip());

    const path = args.next() orelse return Error.MissingFilePath;
    std.fs.cwd().access(path, .{}) catch |err| {
        std.log.err("Error occured when accessing the specified file '{s}': {}", .{ path, err });
    };
    const absolute_path = std.fs.cwd().realpathAlloc(gpa, path[0..path.len]) catch |err| {
        std.log.err("Could not determine absolute path of provided file - {}", .{err});
        return;
    };
    var file = try std.fs.openFileAbsolute(absolute_path, std.fs.File.OpenFlags{ .mode = .read_only });
    defer file.close();

    var reader_buffer: [4096]u8 = undefined;
    var reader = file.reader(&reader_buffer);

    var cmd = try std.ArrayList(u8).initCapacity(gpa, 40);
    defer cmd.deinit(gpa);
    var tests = try std.ArrayList([]const u8).initCapacity(gpa, 10);
    defer tests.deinit(gpa);

    var ret_zero: ?bool = null;

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        if (std.mem.startsWith(u8, line, "// ")) {
            const sub_slice = line[3..];
            if (std.mem.startsWith(u8, sub_slice, "CMD: ")) {
                const cmd_definition = sub_slice[5..];
                for (cmd_definition) |c| {
                    if (c == '%') {
                        try cmd.appendSlice(gpa, absolute_path);
                    } else {
                        try cmd.append(gpa, c);
                    }
                }
            } else if (std.mem.startsWith(u8, sub_slice, "RET: ")) {
                const ret_definition = sub_slice[5..];
                if (ret_zero != null) {
                    std.log.err("Cannot configure multiple return values", .{});
                    return Error.InvalidCheck;
                }
                if (std.mem.eql(u8, ret_definition, "ZERO")) {
                    ret_zero = true;
                } else if (std.mem.eql(u8, ret_definition, "NON-ZERO")) {
                    ret_zero = false;
                } else {
                    std.log.err("Return value check can only be ZERO or NON-ZERO", .{});
                    return Error.InvalidCheck;
                }
            } else if (std.mem.startsWith(u8, sub_slice, "TEST: ")) {
                const test_definition = sub_slice[6..];
                try tests.append(gpa, test_definition);
            }
        }
        reader.interface.discardAll(1) catch |err| switch (err) {
            std.io.Reader.Error.EndOfStream => break,
            std.io.Reader.Error.ReadFailed => return err,
        };
    } else |err| switch (err) {
        std.io.Reader.Error.EndOfStream => {},
        else => return err,
    }

    const out = try std.process.Child.run(.{
        .allocator = gpa,
        .argv = &.{ "bash", "-c", cmd.items },
    });

    var char_idx: usize = 0;
    var test_idx: usize = 0;
    var in_test_idx: usize = 0;
    while (test_idx < tests.items.len and char_idx < out.stdout.len) {
        const test_str = tests.items[test_idx];
        if (in_test_idx >= test_str.len) {
            test_idx += 1;
            in_test_idx = 0;
            continue;
        }

        if (in_test_idx == 0) {
            while (std.ascii.isWhitespace(out.stdout[char_idx])) {
                char_idx += 1;
                if (char_idx >= out.stdout.len) {
                    return Error.CheckFailed;
                }
            }
        }
        if (out.stdout[char_idx] == test_str[in_test_idx]) {
            char_idx += 1;
            in_test_idx += 1;
        } else {
            const out_start = char_idx - in_test_idx;
            const out_slice = out.stdout[out_start..(out_start + test_str.len)];
            std.log.err("Pattern to match:  '{s}'", .{test_str});
            std.log.err("Output by command: '{s}'", .{out_slice});
            return Error.CheckFailed;
        }
    }
}
