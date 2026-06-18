const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(bool, "use_llvm", "Force using LLVM as the codegen backend") orelse true;
    const use_lld = b.option(bool, "use_lld", "Force using LLD as the linker") orelse true;

    const mod = b.addModule("pgwire", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const zio = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    }).module("zio");
    mod.addImport("zio", zio);

    const exe = b.addExecutable(.{
        .name = "pgwire",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pgwire", .module = mod },
                .{ .name = "zio", .module = zio },
            },
        }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
