# zpdf

A comprehensive, zero-dependency PDF library for creating, parsing, modifying, and manipulating PDF documents in pure Zig.

<!-- Badges -->
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.15.0+-f7a41d.svg)](https://ziglang.org/)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WASM-lightgrey)

---

## Features

### PDF Creation
- Create PDF documents from scratch with full control over structure
- Add multiple pages with configurable sizes and orientations
- Set document metadata (title, author, subject, keywords, creator)
- Stream-based output for memory-efficient generation

### PDF Parsing
- Parse existing PDF files into structured document objects
- Extract text content from pages
- Read document metadata and properties
- Navigate page trees and object references
- Handle cross-reference tables and streams

### PDF Modification
- Merge multiple PDF documents into one
- Split documents by page ranges
- Add watermarks (text and image) to existing pages
- Insert, remove, and reorder pages

### Security
- AES-128 and AES-256 encryption
- RC4 encryption (40-bit and 128-bit)
- User and owner passwords
- Granular permissions (print, copy, modify, annotate, fill forms, extract, assemble)

### Advanced
- Interactive forms (AcroForms): text fields, checkboxes, radio buttons, dropdowns, buttons
- Annotations: links, text notes, highlights, underlines, strikeouts
- Bookmarks / document outline with nested hierarchy
- Barcode generation: Code 128, Code 39, EAN-13, EAN-8, UPC-A, QR Code, Data Matrix
- Optional Content Groups (layers) for toggling visibility
- Tagged PDF / PDF/UA for accessibility compliance
- XMP metadata

### Font Support
- All 14 PDF standard fonts (Helvetica, Times, Courier, Symbol, ZapfDingbats and variants)
- Built-in font metrics for precise text measurement
- Text wrapping with word-boundary and character-boundary breaking
- Kerning and character spacing control

### Graphics
- Lines, rectangles, circles, ellipses, polygons
- Bezier curves and custom paths via PathBuilder
- Fill and stroke with configurable colors and line styles
- Dashed lines, line caps, line joins
- Graphics state stack (save/restore)
- Coordinate transforms (translate, rotate, scale)

### Color
- RGB, CMYK, and grayscale color spaces
- Named color presets
- Opacity / transparency support

### Images
- JPEG embedding
- PNG embedding (with alpha channel)
- Image scaling and positioning
- Raw pixel data support

### Tables
- Row and column layout with configurable widths
- Cell padding and alignment (left, center, right)
- Borders with per-cell styling
- Header rows and column spans
- Automatic page breaks for long tables
- Alternating row colors

---

## Installation

Add zpdf as a dependency in your `build.zig.zon`:

```zig
// In your build.zig.zon
.dependencies = .{
    .zpdf = .{
        .url = "https://github.com/meszmate/zpdf/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zpdf_mod = b.dependency("zpdf", .{}).module("zpdf");
exe.root_module.addImport("zpdf", zpdf_mod);
```

---

## Quick Start

```zig
const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Hello World");
    var page = try doc.addPage(.a4);
    try page.drawText("Hello, zpdf!", .{
        .x = 50,
        .y = 750,
        .font = .helvetica,
        .font_size = 24,
        .color = zpdf.rgb(0, 51, 153),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("hello.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);
}
```

---

## Examples

### Drawing Shapes

```zig
const zpdf = @import("zpdf");

var page = try doc.addPage(.a4);

// Rectangle
try page.drawRect(.{
    .x = 50,
    .y = 700,
    .width = 200,
    .height = 100,
    .fill_color = zpdf.rgb(230, 240, 255),
    .stroke_color = zpdf.rgb(0, 51, 153),
    .line_width = 2,
});

// Circle
try page.drawCircle(.{
    .cx = 400,
    .cy = 750,
    .radius = 50,
    .fill_color = zpdf.cmyk(0, 0.8, 0.9, 0),
});

// Line
try page.drawLine(.{
    .x1 = 50,
    .y1 = 600,
    .x2 = 550,
    .y2 = 600,
    .color = zpdf.gray(0.5),
    .line_width = 1,
    .dash_pattern = &.{ 5, 3 },
});
```

### Tables

```zig
const zpdf = @import("zpdf");

var table = zpdf.Table.init(allocator, .{
    .columns = &.{
        .{ .width = .{ .fixed = 60 } },
        .{ .width = .{ .flex = 1 } },
        .{ .width = .{ .fixed = 80 }, .alignment = .right },
    },
    .header_style = .{
        .font = .helvetica_bold,
        .fill_color = zpdf.rgb(0, 51, 153),
        .text_color = zpdf.rgb(255, 255, 255),
    },
    .alternating_row_colors = .{
        zpdf.rgb(255, 255, 255),
        zpdf.rgb(240, 245, 255),
    },
});
defer table.deinit();

try table.addHeader(&.{ "ID", "Name", "Price" });
try table.addRow(&.{ "001", "Widget", "$9.99" });
try table.addRow(&.{ "002", "Gadget", "$24.99" });
try table.addRow(&.{ "003", "Doohickey", "$4.99" });

try table.render(page, .{ .x = 50, .y = 700 });
```

### Images

```zig
const zpdf = @import("zpdf");

// Embed from file bytes
const jpeg_data = try std.fs.cwd().readFileAlloc(allocator, "photo.jpg", 10 * 1024 * 1024);
defer allocator.free(jpeg_data);

const image = try doc.addImage(.{
    .data = jpeg_data,
    .format = .jpeg,
});

try page.drawImage(image, .{
    .x = 50,
    .y = 500,
    .width = 200,
    .height = 150,
});
```

### Forms

```zig
const zpdf = @import("zpdf");

var form = try doc.createForm();

try form.addTextField(.{
    .name = "full_name",
    .page = page,
    .rect = .{ .x = 100, .y = 700, .width = 200, .height = 24 },
    .default_value = "",
    .font_size = 12,
});

try form.addCheckbox(.{
    .name = "agree_terms",
    .page = page,
    .rect = .{ .x = 100, .y = 660, .width = 16, .height = 16 },
    .checked = false,
});

try form.addDropdown(.{
    .name = "country",
    .page = page,
    .rect = .{ .x = 100, .y = 620, .width = 200, .height = 24 },
    .options = &.{ "United States", "Canada", "United Kingdom", "Germany", "Japan" },
    .selected = 0,
});
```

### Barcodes

```zig
const zpdf = @import("zpdf");

// Code 128
try page.drawBarcode(.{
    .type = .code128,
    .data = "ZPDF-2026",
    .x = 50,
    .y = 700,
    .width = 200,
    .height = 60,
    .show_text = true,
});

// QR Code
try page.drawBarcode(.{
    .type = .qr,
    .data = "https://github.com/meszmate/zpdf",
    .x = 50,
    .y = 600,
    .width = 100,
    .height = 100,
});

// EAN-13
try page.drawBarcode(.{
    .type = .ean13,
    .data = "5901234123457",
    .x = 50,
    .y = 500,
    .width = 180,
    .height = 70,
    .show_text = true,
});
```

### Encryption

```zig
const zpdf = @import("zpdf");

doc.setEncryption(.{
    .method = .aes256,
    .user_password = "read-only",
    .owner_password = "full-access",
    .permissions = .{
        .print = true,
        .copy = false,
        .modify = false,
        .annotate = true,
        .fill_forms = true,
        .extract = false,
        .assemble = false,
    },
});
```

### Merging PDFs

```zig
const zpdf = @import("zpdf");

const pdf1_bytes = try std.fs.cwd().readFileAlloc(allocator, "doc1.pdf", 50 * 1024 * 1024);
defer allocator.free(pdf1_bytes);
const pdf2_bytes = try std.fs.cwd().readFileAlloc(allocator, "doc2.pdf", 50 * 1024 * 1024);
defer allocator.free(pdf2_bytes);

var doc1 = try zpdf.Parser.parse(allocator, pdf1_bytes);
defer doc1.deinit();
var doc2 = try zpdf.Parser.parse(allocator, pdf2_bytes);
defer doc2.deinit();

var merged = try zpdf.merge(allocator, &.{ doc1, doc2 });
defer merged.deinit();

const output = try merged.save(allocator);
defer allocator.free(output);
```

### Splitting PDFs

```zig
const zpdf = @import("zpdf");

var doc = try zpdf.Parser.parse(allocator, pdf_bytes);
defer doc.deinit();

// Extract pages 1-3
var subset = try doc.extractPages(allocator, .{ .start = 0, .end = 3 });
defer subset.deinit();

const output = try subset.save(allocator);
defer allocator.free(output);
```

### Parsing PDFs

```zig
const zpdf = @import("zpdf");

const pdf_bytes = try std.fs.cwd().readFileAlloc(allocator, "input.pdf", 50 * 1024 * 1024);
defer allocator.free(pdf_bytes);

var doc = try zpdf.Parser.parse(allocator, pdf_bytes);
defer doc.deinit();

// Read metadata
if (doc.getTitle()) |title| {
    std.debug.print("Title: {s}\n", .{title});
}
std.debug.print("Pages: {d}\n", .{doc.getPageCount()});

// Extract text from each page
for (0..doc.getPageCount()) |i| {
    const text = try doc.getPageText(allocator, i);
    defer allocator.free(text);
    std.debug.print("Page {d}: {s}\n", .{ i + 1, text });
}
```

### Watermarks

```zig
const zpdf = @import("zpdf");

var doc = try zpdf.Parser.parse(allocator, pdf_bytes);
defer doc.deinit();

try zpdf.watermark(doc, .{
    .text = "CONFIDENTIAL",
    .font_size = 60,
    .color = zpdf.rgba(255, 0, 0, 0.15),
    .rotation = 45,
    .position = .center,
});
```

### Bookmarks

```zig
const zpdf = @import("zpdf");

var outline = try doc.createOutline();
const chapter1 = try outline.addItem("Chapter 1: Introduction", .{ .page = 0, .y = 750 });
try chapter1.addChild("1.1 Overview", .{ .page = 0, .y = 500 });
try chapter1.addChild("1.2 Getting Started", .{ .page = 1, .y = 750 });

const chapter2 = try outline.addItem("Chapter 2: Advanced Topics", .{ .page = 2, .y = 750 });
try chapter2.addChild("2.1 Performance", .{ .page = 2, .y = 500 });
```

### Annotations

```zig
const zpdf = @import("zpdf");

// Link annotation
try page.addAnnotation(.{
    .type = .link,
    .rect = .{ .x = 50, .y = 700, .width = 200, .height = 20 },
    .uri = "https://github.com/meszmate/zpdf",
});

// Text note
try page.addAnnotation(.{
    .type = .text_note,
    .rect = .{ .x = 50, .y = 650, .width = 24, .height = 24 },
    .contents = "This section needs review.",
    .color = zpdf.rgb(255, 255, 0),
});

// Highlight
try page.addAnnotation(.{
    .type = .highlight,
    .rect = .{ .x = 50, .y = 600, .width = 300, .height = 16 },
    .color = zpdf.rgba(255, 255, 0, 0.5),
});
```

### Custom Paths

```zig
const zpdf = @import("zpdf");

var path = zpdf.PathBuilder.init();
path.moveTo(100, 700);
path.lineTo(200, 750);
path.curveTo(250, 800, 300, 750, 350, 700);
path.lineTo(350, 600);
path.closePath();

try page.drawPath(path, .{
    .fill_color = zpdf.rgb(200, 220, 255),
    .stroke_color = zpdf.rgb(0, 0, 100),
    .line_width = 2,
});
```

### Layers (Optional Content Groups)

```zig
const zpdf = @import("zpdf");

const draft_layer = try doc.addLayer("Draft Marks", .{ .visible = true });
const print_layer = try doc.addLayer("Print Only", .{ .visible = false, .print = true });

try page.beginLayer(draft_layer);
try page.drawText("DRAFT", .{
    .x = 250,
    .y = 400,
    .font_size = 72,
    .color = zpdf.rgba(255, 0, 0, 0.3),
});
try page.endLayer();

try page.beginLayer(print_layer);
try page.drawText("Printed on: 2026-01-01", .{
    .x = 50,
    .y = 30,
    .font_size = 8,
    .color = zpdf.gray(0.5),
});
try page.endLayer();
```

### Tagged PDF (Accessibility)

```zig
const zpdf = @import("zpdf");

doc.setTagged(true);
doc.setLanguage("en-US");

var page = try doc.addPage(.a4);

try page.beginTag(.h1);
try page.drawText("Document Title", .{
    .x = 50,
    .y = 750,
    .font = .helvetica_bold,
    .font_size = 24,
});
try page.endTag();

try page.beginTag(.p);
try page.drawText("This is an accessible paragraph of text.", .{
    .x = 50,
    .y = 710,
    .font = .helvetica,
    .font_size = 12,
});
try page.endTag();

try page.addImageTag(image, .{
    .alt_text = "A chart showing quarterly revenue growth",
});
```

---

## API Reference

### Document

| Method | Description |
|--------|-------------|
| `Document.init(allocator)` | Create a new empty PDF document |
| `doc.deinit()` | Free all resources |
| `doc.addPage(size)` | Add a new page with the given size |
| `doc.setTitle(title)` | Set the document title |
| `doc.setAuthor(author)` | Set the document author |
| `doc.setSubject(subject)` | Set the document subject |
| `doc.setKeywords(keywords)` | Set the document keywords |
| `doc.setCreator(creator)` | Set the creator application name |
| `doc.setEncryption(options)` | Enable encryption with given options |
| `doc.addImage(options)` | Add an image resource to the document |
| `doc.addLayer(name, options)` | Add an optional content group |
| `doc.createForm()` | Create an interactive form |
| `doc.createOutline()` | Create a document outline (bookmarks) |
| `doc.setTagged(enabled)` | Enable tagged PDF structure |
| `doc.setLanguage(lang)` | Set the document language |
| `doc.save(allocator)` | Serialize the document to PDF bytes |
| `doc.getPageCount()` | Return the number of pages |
| `doc.extractPages(allocator, range)` | Extract a subset of pages |

### Page

| Method | Description |
|--------|-------------|
| `page.drawText(text, options)` | Draw text at a position |
| `page.drawRect(options)` | Draw a rectangle |
| `page.drawCircle(options)` | Draw a circle |
| `page.drawEllipse(options)` | Draw an ellipse |
| `page.drawLine(options)` | Draw a line |
| `page.drawPolygon(points, options)` | Draw a polygon |
| `page.drawImage(image, options)` | Draw an image |
| `page.drawPath(path, options)` | Draw a custom path |
| `page.drawBarcode(options)` | Draw a barcode |
| `page.addAnnotation(options)` | Add an annotation |
| `page.beginLayer(layer)` | Begin optional content group |
| `page.endLayer()` | End optional content group |
| `page.beginTag(tag)` | Begin a structure tag |
| `page.endTag()` | End a structure tag |
| `page.addImageTag(image, options)` | Add an accessible image tag |
| `page.saveState()` | Save the graphics state |
| `page.restoreState()` | Restore the graphics state |
| `page.translate(tx, ty)` | Apply translation transform |
| `page.rotate(angle)` | Apply rotation transform |
| `page.scale(sx, sy)` | Apply scale transform |

### Table

| Method | Description |
|--------|-------------|
| `Table.init(allocator, options)` | Create a table with column definitions |
| `table.deinit()` | Free table resources |
| `table.addHeader(cells)` | Add a header row |
| `table.addRow(cells)` | Add a data row |
| `table.render(page, position)` | Render the table onto a page |

### PathBuilder

| Method | Description |
|--------|-------------|
| `PathBuilder.init()` | Create a new path |
| `path.moveTo(x, y)` | Move to a point |
| `path.lineTo(x, y)` | Draw a line to a point |
| `path.curveTo(...)` | Draw a cubic Bezier curve |
| `path.closePath()` | Close the current subpath |

### Parser

| Method | Description |
|--------|-------------|
| `Parser.parse(allocator, bytes)` | Parse PDF bytes into a Document |
| `doc.getTitle()` | Get the document title (if set) |
| `doc.getPageText(allocator, index)` | Extract text from a page |

---

## Color Utilities

```zig
// RGB (0-255)
const red = zpdf.rgb(255, 0, 0);
const custom = zpdf.rgb(0, 51, 153);

// RGBA with opacity (0.0-1.0)
const semi = zpdf.rgba(255, 0, 0, 0.5);

// CMYK (0.0-1.0)
const cyan = zpdf.cmyk(1.0, 0, 0, 0);

// Grayscale (0.0 = black, 1.0 = white)
const mid_gray = zpdf.gray(0.5);
```

---

## Page Sizes

| Constant | Dimensions (points) | Millimeters |
|----------|---------------------|-------------|
| `.a3` | 842 x 1191 | 297 x 420 |
| `.a4` | 595 x 842 | 210 x 297 |
| `.a5` | 420 x 595 | 148 x 210 |
| `.a6` | 298 x 420 | 105 x 148 |
| `.letter` | 612 x 792 | 216 x 279 |
| `.legal` | 612 x 1008 | 216 x 356 |
| `.tabloid` | 792 x 1224 | 279 x 432 |
| `.executive` | 522 x 756 | 184 x 267 |
| `.b4` | 709 x 1001 | 250 x 353 |
| `.b5` | 499 x 709 | 176 x 250 |

Custom sizes:

```zig
var page = try doc.addPage(.{ .custom = .{ .width = 400, .height = 600 } });
```

---

## Standard Fonts

| Enum | Font Name |
|------|-----------|
| `.helvetica` | Helvetica |
| `.helvetica_bold` | Helvetica-Bold |
| `.helvetica_italic` | Helvetica-Oblique |
| `.helvetica_bold_italic` | Helvetica-BoldOblique |
| `.times` | Times-Roman |
| `.times_bold` | Times-Bold |
| `.times_italic` | Times-Italic |
| `.times_bold_italic` | Times-BoldItalic |
| `.courier` | Courier |
| `.courier_bold` | Courier-Bold |
| `.courier_italic` | Courier-Oblique |
| `.courier_bold_italic` | Courier-BoldOblique |
| `.symbol` | Symbol |
| `.zapf_dingbats` | ZapfDingbats |

---

## Platform Support

zpdf is a pure Zig library with no platform-specific code. It works on any target supported by the Zig standard library:

- **Zig version**: 0.15.0+
- **Targets**: Linux, macOS, Windows, FreeBSD, WebAssembly, and any other target with `std` library support
- **Architecture**: x86_64, aarch64, wasm32, and others

---

## Performance

zpdf is designed for efficiency:

- **Zero allocations** in hot paths where possible
- **Streaming output** to minimize peak memory usage
- **Deflate compression** for reduced file sizes
- **Lazy parsing** -- only parse objects when accessed
- **No garbage collection** -- deterministic memory management via allocators
- **Comptime-known layouts** -- leverages Zig's comptime for zero-overhead abstractions

---

## Building & Testing

```bash
# Build the library
zig build

# Run all tests
zig build test

# Run a specific example
zig build run-create_basic

# Build in release mode
zig build -Doptimize=ReleaseFast
```

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
