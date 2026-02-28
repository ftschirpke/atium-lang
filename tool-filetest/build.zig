// SPDX-License-Identifier: MIT
const std = @import("std");

const CompilerBuildError = error{MissingLibrary};

pub fn build_subproject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CompilerBuildError!void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("tool-filetest/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "filetest",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}
