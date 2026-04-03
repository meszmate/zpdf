const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Step 1: Create a PDF document to validate
    std.debug.print("=== Creating a test PDF ===\n", .{});

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Validation Test");
    const page = try doc.addPage(.a4);
    try page.drawText("Hello, validator!", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 18,
    });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    std.debug.print("Generated PDF: {d} bytes\n\n", .{pdf_bytes.len});

    // Step 2: Validate the generated PDF
    std.debug.print("=== Validating PDF ===\n", .{});

    var result = try zpdf.validatePdf(allocator, pdf_bytes, .{});
    defer result.deinit();

    std.debug.print("Valid: {}\n", .{result.is_valid});
    std.debug.print("Issues found: {d}\n\n", .{result.issues.len});

    for (result.issues) |issue| {
        const severity_str = switch (issue.severity) {
            .error_ => "ERROR",
            .warning => "WARNING",
            .info => "INFO",
        };
        if (issue.byte_offset) |offset| {
            std.debug.print("[{s}] {s} (at byte {d})\n", .{ severity_str, issue.message, offset });
        } else {
            std.debug.print("[{s}] {s}\n", .{ severity_str, issue.message });
        }
    }

    // Step 3: Validate with strict mode
    std.debug.print("\n=== Strict validation ===\n", .{});

    var strict_result = try zpdf.validatePdf(allocator, pdf_bytes, .{ .strict = true });
    defer strict_result.deinit();

    std.debug.print("Valid (strict): {}\n", .{strict_result.is_valid});
    std.debug.print("Issues found: {d}\n\n", .{strict_result.issues.len});

    for (strict_result.issues) |issue| {
        const severity_str = switch (issue.severity) {
            .error_ => "ERROR",
            .warning => "WARNING",
            .info => "INFO",
        };
        if (issue.byte_offset) |offset| {
            std.debug.print("[{s}] {s} (at byte {d})\n", .{ severity_str, issue.message, offset });
        } else {
            std.debug.print("[{s}] {s}\n", .{ severity_str, issue.message });
        }
    }

    // Step 4: Validate invalid data
    std.debug.print("\n=== Validating invalid data ===\n", .{});

    var bad_result = try zpdf.validatePdf(allocator, "not a pdf", .{});
    defer bad_result.deinit();

    std.debug.print("Valid: {}\n", .{bad_result.is_valid});
    std.debug.print("Issues found: {d}\n", .{bad_result.issues.len});
    for (bad_result.issues) |issue| {
        const severity_str = switch (issue.severity) {
            .error_ => "ERROR",
            .warning => "WARNING",
            .info => "INFO",
        };
        std.debug.print("[{s}] {s}\n", .{ severity_str, issue.message });
    }

    std.debug.print("\nValidation complete.\n", .{});
}
