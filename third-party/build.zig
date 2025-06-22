const std = @import("std");

const LLVMBuildError = error{OutOfMemory};

pub const LLVMBuild = struct {
    build_step: *std.Build.Step.Run,
    build_path: std.Build.LazyPath,
    install_path: std.Build.LazyPath,
};

pub fn build_llvm(b: *std.Build, optimize: std.builtin.OptimizeMode) LLVMBuildError!LLVMBuild {
    const cwd = b.path("third-party/");
    const name = "llvm";

    const src_path = try cwd.join(b.allocator, "llvm-project");
    const src = try src_path.join(b.allocator, name);

    const build_type = switch (optimize) {
        std.builtin.OptimizeMode.Debug => "Debug",
        std.builtin.OptimizeMode.ReleaseSmall => "MinSizeRel",
        else => "Release",
    };

    const llvm_config = b.addSystemCommand(&.{
        "cmake",
        "-G",
        "Ninja",
        "-DLLVM_ENABLE_PROJECTS=mlir",
        "-DLLVM_ENABLE_ASSERTIONS=ON",
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{build_type}),
        "-DLLVM_TOOL_LLI_BUILD=OFF",
        "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_INCLUDE_UTILS=OFF",
        "-DLLVM_BUILD_TOOLS=OFF",
    });
    llvm_config.addArg("-B");
    const build_path = llvm_config.addOutputDirectoryArg("llvm_build");
    const install_path = llvm_config.addPrefixedOutputDirectoryArg("-DCMAKE_INSTALL_PREFIX=", "llvm_install");
    llvm_config.addArg("-S");
    llvm_config.addDirectoryArg(src);

    llvm_config.step.name = "configure-llvm-build";
    // llvm_config.expectExitCode(0);

    const llvm_build = b.addSystemCommand(&.{
        "cmake",
    });
    llvm_build.addArg("--build");
    llvm_build.addDirectoryArg(build_path);
    llvm_build.addArg("--target");
    llvm_build.addArg("install");

    llvm_build.step.name = "run-llvm-build";
    // llvm_build.expectExitCode(0);

    llvm_build.step.dependOn(&llvm_config.step);

    return LLVMBuild{
        .build_step = llvm_build,
        .build_path = build_path,
        .install_path = install_path,
    };
}
