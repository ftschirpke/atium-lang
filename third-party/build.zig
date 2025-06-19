const std = @import("std");

const build_dir = "build";
const install_dir = "install";

const LLVMBuildError = error{OutOfMemory};

pub fn build_llvm(b: *std.Build, optimize: std.builtin.OptimizeMode) LLVMBuildError!*std.Build.Step.Run {
    const cwd = b.path("third-party/");
    const name = "llvm";

    const src_path = try cwd.join(b.allocator, "llvm-project");
    const src = try src_path.join(b.allocator, name);
    const build_path = try cwd.join(b.allocator, build_dir);
    const build = try build_path.join(b.allocator, name);
    const install_path = try cwd.join(b.allocator, install_dir);
    const install = try install_path.join(b.allocator, name);

    var build_type: []const u8 = undefined;
    switch (optimize) {
        std.builtin.OptimizeMode.Debug => {
            build_type = "Debug";
        },
        std.builtin.OptimizeMode.ReleaseSmall => {
            build_type = "MinSizeRel";
        },
        else => {
            build_type = "Release";
        },
    }

    const llvm_config = b.addSystemCommand(&.{
        "cmake",
        "-G",
        "Ninja",
        "-S",
        src.getPath(b),
        "-B",
        build.getPath(b),
        "-DLLVM_ENABLE_PROJECTS='mlir'",
        b.fmt("-DCMAKE_INSTALL_PREFIX={s}", .{install.getPath(b)}),
        "-DLLVM_ENABLE_ASSERTIONS=ON",
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{build_type}),
        "-DLLVM_TOOL_LLI_BUILD=OFF",
        "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_INCLUDE_UTILS=OFF",
        "-DLLVM_BUILD_TOOLS=OFF",
    });

    const llvm_build = b.addSystemCommand(&.{
        "cmake",
        "--build",
        build.getPath(b),
        "--target",
        "install",
    });

    llvm_build.step.dependOn(&llvm_config.step);

    return llvm_build;
}
