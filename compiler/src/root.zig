// SPDX-License-Identifier: MIT
const std = @import("std");

pub const collections = @import("collections.zig");
pub const lex = @import("lex.zig");
pub const parse = @import("parse.zig");
pub const sources = @import("sources.zig");

pub export fn sub(a: i32, b: i32) i32 {
    return a - b;
}

test "basic add functionality" {
    try std.testing.expect(sub(3, 7) == -4);
}
