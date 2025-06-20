//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

const cmlir = @cImport({
    @cInclude("mlir-c/Support.h");
});

pub export fn add(a: i32, b: i32) i32 {
    const res = cmlir.mlirLogicalResultSuccess();
    return a + b + res.value;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
