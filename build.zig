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
        "incremental_update",
        "streaming",
        "rich_text",
        "create_gradients",
        "headers_footers",
        "clipping",
        "truetype_fonts",
        "fill_form",
        "fdf_xfdf",
        "digital_signature",
        "pdfa_document",
        "upca_ean8",
        "multi_column",
        "data_matrix",
        "lists",
        "hyphenation",
        "soft_masks",
        "attachments",
        "redaction",
        "named_destinations",
        "linearization",
        "tiling_patterns",
        "transparency",
        "page_templates",
        "page_stamping",
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
        "tests/clip_tests.zig",
        "tests/integration_tests.zig",
        "tests/incremental_tests.zig",
        "tests/stream_writer_tests.zig",
        "tests/rich_text_tests.zig",
        "tests/header_footer_tests.zig",
        "tests/truetype_tests.zig",
        "tests/form_filler_tests.zig",
        "tests/fdf_tests.zig",
        "tests/signature_tests.zig",
        "tests/pdfa_tests.zig",
        "tests/upca_ean8_tests.zig",
        "tests/columns_tests.zig",
        "tests/data_matrix_tests.zig",
        "tests/list_tests.zig",
        "tests/hyphenation_tests.zig",
        "tests/soft_mask_tests.zig",
        "tests/attachment_tests.zig",
        "tests/redaction_tests.zig",
        "tests/destinations_tests.zig",
        "tests/linearization_tests.zig",
        "tests/tiling_pattern_tests.zig",
        "tests/transparency_tests.zig",
        "tests/template_tests.zig",
        "tests/stamper_tests.zig",
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
