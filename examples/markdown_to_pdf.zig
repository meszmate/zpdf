const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const markdown_text =
        \\# Markdown to PDF Demo
        \\
        \\This document was generated from **Markdown** using the *zpdf* library.
        \\
        \\## Features
        \\
        \\The renderer supports a variety of Markdown elements:
        \\
        \\- **Bold text** for emphasis
        \\- *Italic text* for subtle emphasis
        \\- ***Bold and italic*** combined
        \\- `inline code` for technical terms
        \\- [Links](https://github.com/meszmate/zpdf) rendered as blue underlined text
        \\
        \\### Ordered Lists
        \\
        \\1. First item
        \\2. Second item
        \\3. Third item
        \\
        \\### Code Blocks
        \\
        \\```
        \\const std = @import("std");
        \\const zpdf = @import("zpdf");
        \\
        \\pub fn main() !void {
        \\    var renderer = zpdf.MarkdownRenderer.init(allocator, .{});
        \\    const pdf = try renderer.render(markdown);
        \\    defer allocator.free(pdf);
        \\}
        \\```
        \\
        \\### Blockquotes
        \\
        \\> Simplicity is the ultimate sophistication.
        \\> -- Leonardo da Vinci
        \\
        \\---
        \\
        \\## Conclusion
        \\
        \\The Markdown renderer converts plain text into professional PDF documents
        \\with proper formatting, fonts, and layout. It handles automatic pagination
        \\when content exceeds a single page.
        \\
        \\#### H4 Heading Example
        \\
        \\This is a paragraph under an H4 heading to demonstrate all heading levels.
    ;

    var renderer = zpdf.MarkdownRenderer.init(allocator, .{
        .heading_color = zpdf.rgb(0, 51, 102),
        .link_color = zpdf.rgb(0, 102, 204),
    });
    const bytes = try renderer.render(markdown_text);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("markdown_output.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created markdown_output.pdf ({d} bytes)\n", .{bytes.len});
}
