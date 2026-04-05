// SPDX-License-Identifier: MIT
const std = @import("std");

const third_party_build = @import("third-party/build.zig");
const mlir_zig = @import("mlir-zig/build.zig");
const compiler = @import("compiler/build.zig");

const BuildError = error{ MissingLibrary, OutOfMemory, InvalidPath };

pub fn build(b: *std.Build) BuildError!void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm_prefix = b.option([]const u8, "llvm-prefix",
        "Path to pre-installed LLVM/MLIR (e.g. /usr/lib/llvm-21). Skips building from source.");

    const llvm = if (llvm_prefix) |prefix|
        third_party_build.system_llvm(prefix)
    else
        try third_party_build.build_llvm(b, optimize);

    try mlir_zig.build_subproject(b, target, optimize, third_party_build, &llvm);
    try compiler.build_subproject(b, target, optimize);
}
