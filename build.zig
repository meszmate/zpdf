const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library module
    const zpdf_mod = b.addModule("zpdf", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Examples
    const examples = [_][]const u8{
        "create_basic",
        "create_tables",
        "create_graphics",
        "create_forms",
        "create_images",
        "merge_pdfs",
        "encrypt_pdf",
        "watermark",
        "barcodes",
        "parse_pdf",
        "accessibility",
        "create_gradients",
    };

    for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpdf", .module = zpdf_mod },
                },
            }),
        });
        b.installArtifact(example);

        const run_cmd = b.addRunArtifact(example);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(
            b.fmt("run-{s}", .{example_name}),
            b.fmt("Run the {s} example", .{example_name}),
        );
        run_step.dependOn(&run_cmd.step);
    }

    // Tests
    const test_files = [_][]const u8{
        "tests/core_tests.zig",
        "tests/object_tests.zig",
        "tests/writer_tests.zig",
        "tests/color_tests.zig",
        "tests/font_tests.zig",
        "tests/graphics_tests.zig",
        "tests/compress_tests.zig",
        "tests/text_tests.zig",
        "tests/table_tests.zig",
        "tests/security_tests.zig",
        "tests/barcode_tests.zig",
        "tests/utils_tests.zig",
        "tests/gradient_tests.zig",
        "tests/integration_tests.zig",
    };

    const test_step = b.step("test", "Run unit tests");

    for (test_files) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpdf", .module = zpdf_mod },
                },
            }),
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    // Also run tests on the main library
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
}
