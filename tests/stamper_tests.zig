const std = @import("std");
const zpdf = @import("zpdf");

const stampPdf = zpdf.modify.stamper.stampPdf;
const StampOptions = zpdf.modify.stamper.StampOptions;
const StampPosition = zpdf.modify.stamper.StampPosition;

test "stamp foreground onto single-page pdf" {
    const allocator = std.testing.allocator;

    const base = "stream\nBT /F1 12 Tf (Base content) Tj ET\nendstream";
    const stamp = "stream\n0.8 0.2 0.2 rg\nBT /F1 36 Tf (STAMP) Tj ET\nendstream";

    const result = try stampPdf(allocator, base, stamp, .{ .position = .foreground });
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "(Base content) Tj") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "(STAMP) Tj") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "stamp background onto single-page pdf" {
    const allocator = std.testing.allocator;

    const base = "stream\nBT (Original) Tj ET\nendstream";
    const stamp = "stream\n0.9 g\n0 0 612 792 re f\nendstream";

    const result = try stampPdf(allocator, base, stamp, .{ .position = .background });
    defer allocator.free(result);

    // Background stamp appears after "stream\n" and before original content
    const stamp_pos = std.mem.indexOf(u8, result, "0 0 612 792 re f").?;
    const orig_pos = std.mem.indexOf(u8, result, "(Original) Tj").?;
    try std.testing.expect(stamp_pos < orig_pos);
}

test "stamp onto multi-stream pdf" {
    const allocator = std.testing.allocator;

    const base = "stream\nBT (Page1) Tj ET\nendstream\nstream\nBT (Page2) Tj ET\nendstream";
    const stamp = "stream\nBT (S) Tj ET\nendstream";

    const result = try stampPdf(allocator, base, stamp, .{ .position = .foreground });
    defer allocator.free(result);

    // Count occurrences of stamp marker
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, result[search_pos..], "(S) Tj")) |idx| {
        count += 1;
        search_pos += idx + 6;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "stamp invalid inputs" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.InvalidPdf, stampPdf(allocator, "", "stream\nx\nendstream", .{}));
    try std.testing.expectError(error.InvalidStampPdf, stampPdf(allocator, "stream\nx\nendstream", "", .{}));
}

test "stamp default options are foreground page 0" {
    const opts = StampOptions{};
    try std.testing.expectEqual(StampPosition.foreground, opts.position);
    try std.testing.expectEqual(@as(usize, 0), opts.stamp_page_index);
}
