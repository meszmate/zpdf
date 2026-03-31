const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const StandardFont = zpdf.standard_fonts.StandardFont;

test "pdfName returns correct font names" {
    try testing.expectEqualStrings("Helvetica", StandardFont.helvetica.pdfName());
    try testing.expectEqualStrings("Courier-Bold", StandardFont.courier_bold.pdfName());
    try testing.expectEqualStrings("Times-Roman", StandardFont.times_roman.pdfName());
    try testing.expectEqualStrings("ZapfDingbats", StandardFont.zapf_dingbats.pdfName());
}

test "isFixedPitch for courier variants" {
    try testing.expect(StandardFont.courier.isFixedPitch());
    try testing.expect(StandardFont.courier_bold.isFixedPitch());
    try testing.expect(StandardFont.courier_oblique.isFixedPitch());
    try testing.expect(!StandardFont.helvetica.isFixedPitch());
    try testing.expect(!StandardFont.times_roman.isFixedPitch());
}

test "charWidth: courier is always 600" {
    try testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth('A'));
    try testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth(' '));
    try testing.expectEqual(@as(u16, 600), StandardFont.courier.charWidth('z'));
}

test "charWidth: helvetica specific characters" {
    try testing.expectEqual(@as(u16, 278), StandardFont.helvetica.charWidth(' '));
    try testing.expectEqual(@as(u16, 667), StandardFont.helvetica.charWidth('A'));
    try testing.expectEqual(@as(u16, 556), StandardFont.helvetica.charWidth('a'));
}

test "textWidth calculates correctly" {
    // "Hello" in Helvetica: H=722 e=556 l=222 l=222 o=556 = 2278
    const w = StandardFont.helvetica.textWidth("Hello", 12.0);
    try testing.expectApproxEqAbs(@as(f32, 27.336), w, 0.01);
}

test "ascender and descender values" {
    try testing.expectEqual(@as(i16, 718), StandardFont.helvetica.ascender());
    try testing.expectEqual(@as(i16, -207), StandardFont.helvetica.descender());
    try testing.expectEqual(@as(i16, 629), StandardFont.courier.ascender());
    try testing.expectEqual(@as(i16, 33), StandardFont.helvetica.lineGap());
}
