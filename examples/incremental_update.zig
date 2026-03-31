const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const IncrementalUpdate = zpdf.IncrementalUpdate;
    const MetadataUpdate = zpdf.MetadataUpdate;
    const updateMetadataIncremental = zpdf.modify.incremental.updateMetadataIncremental;

    // Step 1: Create a simple PDF document
    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Original Document");
    const page = try doc.addPage(PageSize.a4);

    const font_handle = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(font_handle.font.pdfName(), font_handle.ref);

    try page.drawText("This is the original document content.", .{
        .x = 72,
        .y = 720,
        .font = .helvetica,
        .font_size = 16,
        .color = color.rgb(0, 0, 0),
    });

    const original_bytes = try doc.save(allocator);
    defer allocator.free(original_bytes);

    std.debug.print("Original PDF size: {d} bytes\n", .{original_bytes.len});

    // Step 2: Apply an incremental metadata update using the convenience function
    const updated_bytes = try updateMetadataIncremental(allocator, original_bytes, MetadataUpdate{
        .title = "Updated Document Title",
        .author = "zpdf Incremental Update Example",
        .producer = "zpdf library",
    });
    defer allocator.free(updated_bytes);

    std.debug.print("After metadata update: {d} bytes\n", .{updated_bytes.len});

    // Verify original bytes are preserved
    const preserved = std.mem.startsWith(u8, updated_bytes, original_bytes);
    std.debug.print("Original bytes preserved: {}\n", .{preserved});

    // Step 3: Apply another incremental update using the builder API
    var update2 = try IncrementalUpdate.init(allocator, updated_bytes);
    defer update2.deinit();

    // Add a new object
    _ = try update2.addObject(zpdf.core.types.pdfString("Additional data added incrementally"));

    // Update metadata again
    try update2.setMetadata(.{
        .title = "Twice-Updated Document",
        .subject = "Demonstrating multiple incremental updates",
    });

    const final_bytes = try update2.apply();
    defer allocator.free(final_bytes);

    std.debug.print("After second update: {d} bytes\n", .{final_bytes.len});

    // Save to file
    const file = try std.fs.cwd().createFile("incremental_update.pdf", .{});
    defer file.close();
    try file.writeAll(final_bytes);

    std.debug.print("Saved incremental_update.pdf\n", .{});
    std.debug.print("\nThe PDF has been incrementally updated twice.\n", .{});
    std.debug.print("Each update appended new data without modifying the original bytes.\n", .{});
}
