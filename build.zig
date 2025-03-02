const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ✅ Define `zgraph_root` as the main library module
    const zgraph_root = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ✅ Unit Tests for Library (`zgraph_root`)
    const zgraph_root_tests = b.addTest(.{ .root_module = zgraph_root });
    const run_zgraph_root_tests = b.addRunArtifact(zgraph_root_tests);

    // ✅ Build Static Library for `zgraph`
    const lib = b.addStaticLibrary(.{
        .name = "zgraph",
        .root_module = zgraph_root,
    });

    b.installArtifact(lib);

    // ✅ Integration Tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("src/tests/integration/integration_tests.zig"),
    });

    integration_tests.root_module.addImport("zgraph_root", zgraph_root);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    // ✅ CLI Executable (`zgraph_cli`)
    const exe = b.addExecutable(.{
        .name = "zgraph_cli",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zgraph_root", zgraph_root);
    b.installArtifact(exe);

    // ✅ Build Steps
    const run_step = b.step("run", "Run the ZGraph CLI");
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);

    // ✅ Unit Test Step (Runs all tests)
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_zgraph_root_tests.step);

    // ✅ Integration Test Step
    const integration_step = b.step("integration-test", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);
}
