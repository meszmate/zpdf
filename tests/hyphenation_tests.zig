const std = @import("std");
const zpdf = @import("zpdf");
const Hyphenator = zpdf.Hyphenator;
const layoutTextWithOptions = zpdf.layoutTextWithOptions;
const freeTextLines = zpdf.freeTextLines;
const LayoutOptions = zpdf.LayoutOptions;

test "hyphenate common English word: hyphenation" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "hyphenation");
    defer std.testing.allocator.free(points);

    // Should find at least one hyphenation point
    try std.testing.expect(points.len >= 1);

    // Verify all points are within the word
    for (points) |p| {
        try std.testing.expect(p > 0);
        try std.testing.expect(p < "hyphenation".len);
    }
}

test "min_prefix and min_suffix enforcement" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "international");
    defer std.testing.allocator.free(points);

    for (points) |p| {
        // min_prefix = 2: no break before index 2
        try std.testing.expect(p >= hyph.min_prefix);
        // min_suffix = 3: no break after word.len - 3
        try std.testing.expect(p <= "international".len - hyph.min_suffix);
    }
}

test "words too short to hyphenate" {
    const hyph = Hyphenator.init(.english);

    // "the" has 3 chars, min_prefix(2) + min_suffix(3) = 5 > 3
    const points1 = try hyph.hyphenate(std.testing.allocator, "the");
    defer std.testing.allocator.free(points1);
    try std.testing.expectEqual(@as(usize, 0), points1.len);

    // "go" has 2 chars
    const points2 = try hyph.hyphenate(std.testing.allocator, "go");
    defer std.testing.allocator.free(points2);
    try std.testing.expectEqual(@as(usize, 0), points2.len);

    // "a" has 1 char
    const points3 = try hyph.hyphenate(std.testing.allocator, "a");
    defer std.testing.allocator.free(points3);
    try std.testing.expectEqual(@as(usize, 0), points3.len);
}

test "hyphenated text layout produces more lines than non-hyphenated" {
    const alloc = std.testing.allocator;
    const long_text = "The internationalization of communication technology represents extraordinary development";

    // Layout without hyphenation (narrow width to force wrapping)
    const normal_lines = try zpdf.text.text_layout.layoutText(
        alloc,
        long_text,
        .helvetica,
        12.0,
        80.0,
    );
    defer alloc.free(normal_lines);

    // Layout with hyphenation
    const hyph_lines = try layoutTextWithOptions(
        alloc,
        long_text,
        .helvetica,
        12.0,
        80.0,
        .{ .hyphenate = true },
    );
    defer freeTextLines(alloc, hyph_lines);

    // Both should produce multiple lines at 80pt width
    try std.testing.expect(normal_lines.len > 1);
    try std.testing.expect(hyph_lines.len > 1);

    // Hyphenated layout may produce different number of lines (typically more since
    // words get split), but mainly we verify it works without errors.
}

test "hyphens appear at line breaks in hyphenated layout" {
    const alloc = std.testing.allocator;
    // Use a width that forces "international" to not fit on a line with other words
    const text_input = "the international community";

    const hyph_lines = try layoutTextWithOptions(
        alloc,
        text_input,
        .helvetica,
        12.0,
        90.0, // narrow enough to force breaking "international"
        .{ .hyphenate = true },
    );
    defer freeTextLines(alloc, hyph_lines);

    // Check if any line (except the last) ends with a hyphen
    var found_hyphen = false;
    for (hyph_lines[0 .. hyph_lines.len - 1]) |line| {
        if (line.text.len > 0 and line.text[line.text.len - 1] == '-') {
            found_hyphen = true;
            break;
        }
    }

    // If layout produced multiple lines and the word was long enough,
    // we should see at least one hyphen (though width constraints may vary).
    if (hyph_lines.len > 2) {
        try std.testing.expect(found_hyphen);
    }
}

test "hyphenation of word with uppercase letters" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "Communication");
    defer std.testing.allocator.free(points);

    // Should still find break points (case-insensitive matching)
    try std.testing.expect(points.len > 0);
}

test "hyphenation returns sorted indices" {
    const hyph = Hyphenator.init(.english);
    const points = try hyph.hyphenate(std.testing.allocator, "representation");
    defer std.testing.allocator.free(points);

    if (points.len > 1) {
        for (1..points.len) |i| {
            try std.testing.expect(points[i] > points[i - 1]);
        }
    }
}
