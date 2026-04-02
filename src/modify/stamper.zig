const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Where the stamp content is placed relative to existing page content.
pub const StampPosition = enum {
    /// Stamp renders behind existing page content (background).
    background,
    /// Stamp renders on top of existing page content (foreground).
    foreground,
};

/// Options for stamping one PDF onto another.
pub const StampOptions = struct {
    /// Whether the stamp appears in front of or behind page content.
    position: StampPosition = .foreground,
    /// Which page of the stamp PDF to use (0-based index).
    stamp_page_index: usize = 0,
};

/// Stamp (overlay/underlay) content from a stamp PDF onto every page of a base PDF.
///
/// This works by extracting the content stream from the chosen stamp page and
/// injecting it into each content stream of the base PDF.  For `.foreground`
/// the stamp operators are appended just before each `endstream` keyword; for
/// `.background` they are inserted right after each `stream` keyword.
///
/// The stamp content is wrapped in `q` / `Q` (save/restore graphics state) so
/// it does not affect subsequent drawing.
pub fn stampPdf(allocator: Allocator, base_pdf: []const u8, stamp_pdf: []const u8, options: StampOptions) ![]u8 {
    if (base_pdf.len == 0) return error.InvalidPdf;
    if (stamp_pdf.len == 0) return error.InvalidStampPdf;

    // Extract the content stream body from the requested stamp page.
    const stamp_content = try extractStreamContent(allocator, stamp_pdf, options.stamp_page_index);
    defer allocator.free(stamp_content);

    if (stamp_content.len == 0) return error.EmptyStampContent;

    // Build wrapped stamp operators: q ... Q
    var wrapped: ArrayList(u8) = .{};
    defer wrapped.deinit(allocator);
    try wrapped.appendSlice(allocator, "q\n");
    try wrapped.appendSlice(allocator, stamp_content);
    if (stamp_content.len > 0 and stamp_content[stamp_content.len - 1] != '\n') {
        try wrapped.append(allocator, '\n');
    }
    try wrapped.appendSlice(allocator, "Q\n");

    const stamp_ops = wrapped.items;

    // Walk through the base PDF and inject stamp_ops into every stream.
    var output: ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    var pos: usize = 0;
    var injected = false;

    switch (options.position) {
        .foreground => {
            // Inject stamp content just before every "endstream" keyword.
            while (pos < base_pdf.len) {
                if (pos + 9 <= base_pdf.len and std.mem.eql(u8, base_pdf[pos .. pos + 9], "endstream")) {
                    try output.appendSlice(allocator, stamp_ops);
                    try output.appendSlice(allocator, "endstream");
                    pos += 9;
                    injected = true;
                } else {
                    try output.append(allocator, base_pdf[pos]);
                    pos += 1;
                }
            }
        },
        .background => {
            // Inject stamp content right after every "stream\n" marker.
            while (pos < base_pdf.len) {
                if (pos + 7 <= base_pdf.len and std.mem.eql(u8, base_pdf[pos .. pos + 7], "stream\n")) {
                    try output.appendSlice(allocator, "stream\n");
                    try output.appendSlice(allocator, stamp_ops);
                    pos += 7;
                    injected = true;
                } else if (pos + 8 <= base_pdf.len and std.mem.eql(u8, base_pdf[pos .. pos + 8], "stream\r\n")) {
                    try output.appendSlice(allocator, "stream\r\n");
                    try output.appendSlice(allocator, stamp_ops);
                    pos += 8;
                    injected = true;
                } else {
                    try output.append(allocator, base_pdf[pos]);
                    pos += 1;
                }
            }
        },
    }

    if (!injected) {
        // Nothing was modified -- return a copy of the original.
        output.clearRetainingCapacity();
        try output.appendSlice(allocator, base_pdf);
    }

    return output.toOwnedSlice(allocator);
}

/// Extract the body of the Nth content stream from a PDF byte sequence.
/// `stream_index` is 0-based.
fn extractStreamContent(allocator: Allocator, pdf: []const u8, stream_index: usize) ![]u8 {
    var count: usize = 0;
    var pos: usize = 0;

    while (pos < pdf.len) {
        // Look for "stream" followed by a newline (LF or CR-LF).
        if (pos + 7 <= pdf.len and std.mem.eql(u8, pdf[pos .. pos + 6], "stream")) {
            var body_start: usize = pos + 6;
            if (body_start < pdf.len and pdf[body_start] == '\r') body_start += 1;
            if (body_start < pdf.len and pdf[body_start] == '\n') body_start += 1;

            // Find matching "endstream".
            if (std.mem.indexOf(u8, pdf[body_start..], "endstream")) |end_offset| {
                const body_end = body_start + end_offset;

                if (count == stream_index) {
                    // Trim trailing whitespace from body.
                    var trimmed_end = body_end;
                    while (trimmed_end > body_start and (pdf[trimmed_end - 1] == '\n' or pdf[trimmed_end - 1] == '\r' or pdf[trimmed_end - 1] == ' ')) {
                        trimmed_end -= 1;
                    }
                    const content = try allocator.alloc(u8, trimmed_end - body_start);
                    @memcpy(content, pdf[body_start..trimmed_end]);
                    return content;
                }

                count += 1;
                pos = body_end + 9; // skip past "endstream"
            } else {
                break;
            }
        } else {
            pos += 1;
        }
    }

    return error.StampPageNotFound;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "stamper: foreground injection" {
    const allocator = std.testing.allocator;
    const base = "stream\nBT /F1 12 Tf (Hello) Tj ET\nendstream";
    const stamp = "stream\n0.5 0.5 0.5 rg\nBT (Stamp) Tj ET\nendstream";
    const result = try stampPdf(allocator, base, stamp, .{ .position = .foreground });
    defer allocator.free(result);

    // Stamp content should appear before endstream
    try std.testing.expect(std.mem.indexOf(u8, result, "(Stamp) Tj") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "endstream") != null);
    // Original content still present
    try std.testing.expect(std.mem.indexOf(u8, result, "(Hello) Tj") != null);
}

test "stamper: background injection" {
    const allocator = std.testing.allocator;
    const base = "stream\nBT /F1 12 Tf (Hello) Tj ET\nendstream";
    const stamp = "stream\n0.5 g\nBT (BG) Tj ET\nendstream";
    const result = try stampPdf(allocator, base, stamp, .{ .position = .background });
    defer allocator.free(result);

    // Stamp content should appear after "stream\n"
    const stream_pos = std.mem.indexOf(u8, result, "stream\n").?;
    const stamp_pos = std.mem.indexOf(u8, result, "(BG) Tj").?;
    const original_pos = std.mem.indexOf(u8, result, "(Hello) Tj").?;
    try std.testing.expect(stamp_pos > stream_pos);
    try std.testing.expect(stamp_pos < original_pos);
}

test "stamper: empty base pdf" {
    const allocator = std.testing.allocator;
    const result = stampPdf(allocator, "", "stream\nfoo\nendstream", .{});
    try std.testing.expectError(error.InvalidPdf, result);
}

test "stamper: empty stamp pdf" {
    const allocator = std.testing.allocator;
    const result = stampPdf(allocator, "stream\nfoo\nendstream", "", .{});
    try std.testing.expectError(error.InvalidStampPdf, result);
}

test "stamper: graphics state isolation" {
    const allocator = std.testing.allocator;
    const base = "stream\nBT (Page) Tj ET\nendstream";
    const stamp = "stream\n1 0 0 rg\nBT (Red) Tj ET\nendstream";
    const result = try stampPdf(allocator, base, stamp, .{ .position = .foreground });
    defer allocator.free(result);

    // Stamp must be wrapped in q/Q
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "stamper: default options" {
    const opts = StampOptions{};
    try std.testing.expectEqual(StampPosition.foreground, opts.position);
    try std.testing.expectEqual(@as(usize, 0), opts.stamp_page_index);
}
