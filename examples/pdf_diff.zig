const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the first PDF
    std.debug.print("=== Creating PDF A ===\n", .{});

    var doc_a = zpdf.Document.init(allocator);
    defer doc_a.deinit();

    doc_a.setTitle("Document A");
    doc_a.setAuthor("zpdf");

    const page_a1 = try doc_a.addPage(.a4);
    try page_a1.drawText("Hello from document A", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 18,
    });

    const bytes_a = try doc_a.save(allocator);
    defer allocator.free(bytes_a);

    // Create the second PDF with differences
    std.debug.print("=== Creating PDF B ===\n", .{});

    var doc_b = zpdf.Document.init(allocator);
    defer doc_b.deinit();

    doc_b.setTitle("Document B");
    doc_b.setAuthor("zpdf");

    const page_b1 = try doc_b.addPage(.letter);
    try page_b1.drawText("Hello from document B", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 18,
    });

    const page_b2 = try doc_b.addPage(.a4);
    try page_b2.drawText("Extra page in B", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 14,
    });

    const bytes_b = try doc_b.save(allocator);
    defer allocator.free(bytes_b);

    // Parse both PDFs
    std.debug.print("=== Parsing PDFs ===\n", .{});

    var parsed_a = try zpdf.parsePdf(allocator, bytes_a);
    defer parsed_a.deinit();

    var parsed_b = try zpdf.parsePdf(allocator, bytes_b);
    defer parsed_b.deinit();

    // Diff them
    std.debug.print("=== Diffing PDFs ===\n", .{});

    var diff = try zpdf.diffPdfs(allocator, &parsed_a, &parsed_b);
    defer diff.deinit();

    std.debug.print("Pages in A: {d}\n", .{diff.page_count_a});
    std.debug.print("Pages in B: {d}\n", .{diff.page_count_b});
    std.debug.print("Identical: {}\n\n", .{diff.isIdentical()});

    std.debug.print("--- Page diffs ---\n", .{});
    for (diff.page_diffs) |pd| {
        std.debug.print("  Page {d}: {s}\n", .{ pd.page_index, @tagName(pd.diff_type) });
    }

    std.debug.print("\n--- Metadata diffs ---\n", .{});
    for (diff.metadata_diffs) |md| {
        if (md.diff_type != .unchanged) {
            std.debug.print("  {s}: {s}\n", .{ md.field, @tagName(md.diff_type) });
        }
    }

    std.debug.print("\n--- Text diffs ---\n", .{});
    for (diff.text_diffs) |td| {
        std.debug.print("  Page {d}: {s}\n", .{ td.page_index, @tagName(td.diff_type) });
    }

    std.debug.print("\nDone.\n", .{});
}
