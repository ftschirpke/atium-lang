// SPDX-License-Identifier: MIT
const std = @import("std");

const LLVMBuildError = error{ OutOfMemory, InvalidPath };

pub const LLVMBuild = struct {
    build_path: std.Build.LazyPath,
    install_path: std.Build.LazyPath,
};

pub fn system_llvm(prefix: []const u8) LLVMBuild {
    const lazy = std.Build.LazyPath{ .cwd_relative = prefix };
    return LLVMBuild{ .build_path = lazy, .install_path = lazy };
}

pub fn build_llvm(b: *std.Build, optimize: std.builtin.OptimizeMode) LLVMBuildError!LLVMBuild {
    const cwd = b.path("third-party");
    const name = "llvm";

    const src_path = cwd.path(b, "llvm-project");
    const src = src_path.path(b, name);

    const build_type = switch (optimize) {
        std.builtin.OptimizeMode.Debug => "Release", // TODO: maybe "Debug"?
        std.builtin.OptimizeMode.ReleaseSmall => "Release", // TODO: maybe "MinSizeRel"?
        else => "Release",
    };

    const llvm_config = b.addSystemCommand(&.{ "cmake", "-G", "Ninja" });
    llvm_config.addArgs(&.{
        "-DLLVM_ENABLE_PROJECTS=mlir",
        "-DLLVM_ENABLE_ASSERTIONS=ON",
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{build_type}),
        "-DLLVM_TOOL_LLI_BUILD=OFF",
        "-DCMAKE_C_COMPILER=clang",
        "-DCMAKE_CXX_COMPILER=clang++",
        "-DLLVM_USE_LINKER=lld",
        "-DLLVM_CCACHE_BUILD=ON",
        "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_INCLUDE_UTILS=OFF",
        "-DLLVM_BUILD_TOOLS=OFF",
        "-DLLVM_ENABLE_OCAMLDOC=OFF",
        "-DLLVM_ENABLE_BINDINGS=OFF",
    });
    llvm_config.addPrefixedDirectoryArg("-S", src);
    const build_path = llvm_config.addPrefixedOutputDirectoryArg("-B", "llvm_build");
    llvm_config.step.name = "configure-llvm-build";
    llvm_config.expectExitCode(0);

    const llvm_build = b.addSystemCommand(&.{ "cmake", "--build" });
    llvm_build.addDirectoryArg(build_path);
    llvm_build.step.name = "run-llvm-build";
    llvm_build.expectExitCode(0);

    const llvm_install = b.addSystemCommand(&.{ "cmake", "--install" });
    llvm_install.addDirectoryArg(build_path);
    const install_path = llvm_install.addPrefixedOutputDirectoryArg("--prefix ", "llvm_install");
    llvm_install.step.dependOn(&llvm_build.step);
    llvm_install.step.name = "install-llvm-build";
    llvm_install.expectExitCode(0);

    return LLVMBuild{
        .build_path = build_path,
        .install_path = install_path,
    };
}
