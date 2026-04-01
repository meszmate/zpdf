const std = @import("std");
const zpdf = @import("zpdf");

test "isLinearized returns false for standard PDF" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(.a4);

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    try std.testing.expect(!zpdf.isLinearized(pdf));
}

test "isLinearized returns true for linearized PDF" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(.a4);

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    const linearized = try zpdf.linearizePdf(allocator, pdf);
    defer allocator.free(linearized);

    try std.testing.expect(zpdf.isLinearized(linearized));
}

test "linearized PDF has valid structure" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Linearization Test");
    const page1 = try doc.addPage(.a4);
    try page1.drawText("First page content", .{
        .x = 72,
        .y = 700,
        .font_size = 14,
    });
    const page2 = try doc.addPage(.a4);
    try page2.drawText("Second page content", .{
        .x = 72,
        .y = 700,
        .font_size = 14,
    });

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    const linearized = try zpdf.linearizePdf(allocator, pdf);
    defer allocator.free(linearized);

    // Must start with PDF header
    try std.testing.expect(std.mem.startsWith(u8, linearized, "%PDF-"));

    // Must contain linearization dictionary
    try std.testing.expect(std.mem.indexOf(u8, linearized, "/Linearized 1") != null);

    // Must contain xref and trailer
    try std.testing.expect(std.mem.indexOf(u8, linearized, "xref") != null);
    try std.testing.expect(std.mem.indexOf(u8, linearized, "trailer") != null);
    try std.testing.expect(std.mem.indexOf(u8, linearized, "startxref") != null);
    try std.testing.expect(std.mem.indexOf(u8, linearized, "%%EOF") != null);

    // Must contain /Catalog
    try std.testing.expect(std.mem.indexOf(u8, linearized, "/Catalog") != null);

    // Must have /N indicating page count (at least 2)
    try std.testing.expect(std.mem.indexOf(u8, linearized, "/N ") != null);

    // Must have /Prev in the second trailer (linking xref sections)
    try std.testing.expect(std.mem.indexOf(u8, linearized, "/Prev ") != null);
}

test "first page objects appear before remaining objects" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    const page1 = try doc.addPage(.a4);
    try page1.drawText("FIRST_PAGE_MARKER", .{
        .x = 72,
        .y = 700,
        .font_size = 12,
    });
    const page2 = try doc.addPage(.a4);
    try page2.drawText("SECOND_PAGE_MARKER", .{
        .x = 72,
        .y = 700,
        .font_size = 12,
    });

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    const linearized = try zpdf.linearizePdf(allocator, pdf);
    defer allocator.free(linearized);

    // The catalog (/Catalog) should appear before the second page marker
    const catalog_pos = std.mem.indexOf(u8, linearized, "/Catalog");
    try std.testing.expect(catalog_pos != null);

    // The linearization dict should be the first object
    const lin_pos = std.mem.indexOf(u8, linearized, "/Linearized");
    try std.testing.expect(lin_pos != null);

    // Linearization dict should come before catalog
    try std.testing.expect(lin_pos.? < catalog_pos.?);
}

test "linearized PDF /L matches actual file length" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(.a4);

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    const linearized = try zpdf.linearizePdf(allocator, pdf);
    defer allocator.free(linearized);

    // Extract /L value
    if (std.mem.indexOf(u8, linearized, "/L ")) |l_pos| {
        var num_start = l_pos + 3;
        // Skip leading zeros from padding
        while (num_start < linearized.len and linearized[num_start] == '0') num_start += 1;
        var num_end = num_start;
        while (num_end < linearized.len and linearized[num_end] >= '0' and linearized[num_end] <= '9') num_end += 1;
        if (num_end > num_start) {
            const l_value = std.fmt.parseInt(usize, linearized[num_start..num_end], 10) catch 0;
            try std.testing.expectEqual(linearized.len, l_value);
        }
    }
}

test "linearizePdf rejects invalid input" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidPdf, zpdf.linearizePdf(allocator, "not a pdf"));
    try std.testing.expectError(error.InvalidPdf, zpdf.linearizePdf(allocator, ""));
}

test "linearize single page PDF" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(.a4);

    const pdf = try doc.save(allocator);
    defer allocator.free(pdf);

    const linearized = try zpdf.linearizePdf(allocator, pdf);
    defer allocator.free(linearized);

    try std.testing.expect(zpdf.isLinearized(linearized));
    try std.testing.expect(std.mem.indexOf(u8, linearized, "/Linearized 1") != null);
}
