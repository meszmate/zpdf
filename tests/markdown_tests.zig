const std = @import("std");
const zpdf = @import("zpdf");

test "markdown renderer init with default options" {
    const renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    try std.testing.expectEqual(zpdf.generators.markdown.MarkdownOptions{}, renderer.options);
}

test "render empty markdown" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render heading only" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("# Title");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
    try std.testing.expect(bytes.len > 200);
}

test "render multiple block types" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const md =
        \\# Heading
        \\
        \\A paragraph with **bold** and *italic* text.
        \\
        \\- Item one
        \\- Item two
        \\
        \\1. First
        \\2. Second
        \\
        \\> A blockquote
        \\
        \\---
        \\
        \\```
        \\code block
        \\```
    ;
    const bytes = try renderer.render(md);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
    try std.testing.expect(bytes.len > 500);
}

test "render with custom options" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{
        .page_size = .letter,
        .body_size = 14,
        .h1_size = 30,
        .heading_color = zpdf.rgb(0, 0, 128),
    });
    const bytes = try renderer.render("# Big Heading\n\nLarger body text.");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render inline code" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("Use `const x = 5` in your code.");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render links" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("Visit [zpdf](https://github.com/meszmate/zpdf) for more.");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render bold italic combined" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("This is ***bold and italic*** text.");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render multiple headings" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const md =
        \\# H1
        \\## H2
        \\### H3
        \\#### H4
    ;
    const bytes = try renderer.render(md);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render horizontal rule" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("Above\n\n---\n\nBelow");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render code block" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const md =
        \\```
        \\fn main() !void {
        \\    std.debug.print("hello\n", .{});
        \\}
        \\```
    ;
    const bytes = try renderer.render(md);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "render blockquote" {
    var renderer = zpdf.MarkdownRenderer.init(std.testing.allocator, .{});
    const bytes = try renderer.render("> This is a blockquote\n> with two lines");
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}
