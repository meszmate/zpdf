# zpdf

A comprehensive, zero-dependency PDF library for creating, parsing, modifying, and manipulating PDF documents in pure TypeScript.

[![npm version](https://img.shields.io/npm/v/zpdf.svg)](https://www.npmjs.com/package/zpdf)
[![license](https://img.shields.io/npm/l/zpdf.svg)](https://github.com/meszmate/zpdf/blob/main/LICENSE)
[![build](https://img.shields.io/github/actions/workflow/status/meszmate/zpdf/ci.yml?branch=main)](https://github.com/meszmate/zpdf/actions)
[![coverage](https://img.shields.io/codecov/c/github/meszmate/zpdf)](https://codecov.io/gh/meszmate/zpdf)

---

## Features

### PDF Creation
- Rich text rendering with alignment, line spacing, and word wrapping
- JPEG and PNG image embedding
- Vector graphics: lines, rectangles, circles, ellipses, polygons, and custom paths
- Tables with headers, column spans, custom styling, and automatic multi-page overflow
- Interactive form fields: text inputs, checkboxes, radio buttons, dropdowns, listboxes, buttons, and signature fields
- Barcodes: Code 39, Code 128, EAN-13, and QR codes
- Watermarks with configurable text, rotation, and opacity
- Repeating headers and footers with page number context

### PDF Parsing
- Full text extraction with position, font, and size information
- Image extraction from existing PDFs
- Metadata and document info reading
- Form field discovery and value reading
- Outline / bookmark tree parsing

### PDF Modification
- Merge multiple PDFs into one (with optional page selection)
- Split PDFs by page or by custom ranges
- Add and remove pages
- Page rotation
- Apply watermarks to existing documents

### Security
- RC4-40 encryption
- RC4-128 encryption
- AES-128 encryption
- AES-256 encryption
- Granular permission control (printing, copying, modifying, annotating, and more)

### Advanced
- Bookmarks / outlines with nested hierarchy
- Annotations: text notes, links, highlights, underlines, strikeouts, stamps, free text, and ink
- Optional content layers (OCG)
- Tagged PDF for accessibility (structure tree with standard tags)
- PDF/A compliance metadata (XMP)
- Linear and radial gradients
- Tiling and shading patterns
- Clipping paths
- Affine transformations (translate, rotate, scale, skew)

### Font Support
- All 14 standard PDF fonts with complete glyph metrics
- TrueType font embedding with automatic subsetting
- Unicode text support via ToUnicode CMaps
- WinAnsi and MacRoman encodings

---

## Installation

```bash
# npm
npm install zpdf

# yarn
yarn add zpdf

# pnpm
pnpm add zpdf
```

---

## Quick Start

```typescript
import { PDFDocument, rgb } from 'zpdf';
import { writeFileSync } from 'node:fs';

const doc = PDFDocument.create({ title: 'Hello World' });
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage({ size: 'A4' });

page.drawText('Hello, zpdf!', {
  x: 50,
  y: 750,
  font,
  fontSize: 24,
  color: rgb(0, 51, 153),
});

const bytes = doc.save();
writeFileSync('hello.pdf', bytes);
```

---

## Examples

### Creating a Document with Text

```typescript
import { PDFDocument, rgb } from 'zpdf';

const doc = PDFDocument.create({
  title: 'Text Demo',
  author: 'zpdf',
});

const font = doc.getStandardFont('Helvetica');
const boldFont = doc.getStandardFont('Helvetica-Bold');
const page = doc.addPage({ size: 'Letter' });

// Title
page.drawText('Document Title', {
  x: 50,
  y: 720,
  font: boldFont,
  fontSize: 28,
  color: rgb(0, 0, 0),
});

// Body paragraph with word wrap
page.drawText(
  'This is a paragraph of text that will automatically wrap within the specified maximum width. zpdf handles line breaking and text layout for you.',
  {
    x: 50,
    y: 680,
    font,
    fontSize: 12,
    maxWidth: 500,
    lineHeight: 18,
    color: rgb(60, 60, 60),
  },
);

// Right-aligned text
page.drawText('Right-aligned text', {
  x: 562,
  y: 600,
  font,
  fontSize: 14,
  alignment: 'right',
});

const bytes = doc.save();
```

### Drawing Shapes

```typescript
import { PDFDocument, rgb, cmyk, PathBuilder } from 'zpdf';

const doc = PDFDocument.create();
const page = doc.addPage({ size: 'A4' });

// Rectangle with fill and stroke
page.drawRect({
  x: 50,
  y: 700,
  width: 200,
  height: 100,
  color: rgb(41, 128, 185),
  borderColor: rgb(0, 0, 0),
  borderWidth: 2,
});

// Circle
page.drawCircle({
  cx: 400,
  cy: 750,
  r: 50,
  color: rgb(231, 76, 60),
});

// Ellipse
page.drawEllipse({
  cx: 300,
  cy: 550,
  rx: 80,
  ry: 40,
  color: cmyk(0, 100, 100, 0),
});

// Line
page.drawLine({
  x1: 50,
  y1: 450,
  x2: 550,
  y2: 450,
  color: rgb(0, 0, 0),
  lineWidth: 1.5,
  dashPattern: [5, 3],
});

// Polygon
page.drawPolygon({
  points: [
    { x: 300, y: 400 },
    { x: 350, y: 320 },
    { x: 250, y: 320 },
  ],
  color: rgb(46, 204, 113),
  borderColor: rgb(39, 174, 96),
  borderWidth: 2,
});

const bytes = doc.save();
```

### Tables

```typescript
import { PDFDocument, Table, TableCell, rgb } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const boldFont = doc.getStandardFont('Helvetica-Bold');
const page = doc.addPage({ size: 'A4' });

const table = new Table({
  borderColor: rgb(200, 200, 200),
  borderWidth: 0.5,
});

table.setColumnWidths([100, 200, 'auto', 100]);

table.addHeaderRow([
  new TableCell('ID', { font: boldFont, backgroundColor: rgb(52, 73, 94), textColor: rgb(255, 255, 255) }),
  new TableCell('Name', { font: boldFont, backgroundColor: rgb(52, 73, 94), textColor: rgb(255, 255, 255) }),
  new TableCell('Description', { font: boldFont, backgroundColor: rgb(52, 73, 94), textColor: rgb(255, 255, 255) }),
  new TableCell('Price', { font: boldFont, backgroundColor: rgb(52, 73, 94), textColor: rgb(255, 255, 255) }),
]);

table.addRow(['001', 'Widget A', 'A high-quality widget', '$19.99']);
table.addRow(['002', 'Widget B', 'An economy widget', '$9.99']);
table.addRow(['003', 'Widget C', 'A premium widget with extras', '$29.99']);

page.drawTable(table, {
  x: 50,
  y: 750,
  width: 495,
  defaultFont: font,
  defaultFontSize: 10,
});

const bytes = doc.save();
```

### Images

```typescript
import { PDFDocument } from 'zpdf';
import { readFileSync } from 'node:fs';

const doc = PDFDocument.create();
const page = doc.addPage({ size: 'A4' });

// Embed a JPEG image
const jpegData = readFileSync('photo.jpg');
const jpegImage = doc.embedJpeg(jpegData);

page.drawImage(jpegImage, {
  x: 50,
  y: 500,
  width: 300,
  height: 200,
});

// Embed a PNG image (with alpha transparency support)
const pngData = readFileSync('logo.png');
const pngImage = await doc.embedPng(pngData);

page.drawImage(pngImage, {
  x: 400,
  y: 700,
  width: 150,
  height: 150,
});

const bytes = doc.save();
```

### Forms

```typescript
import { PDFDocument, rgb } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage({ size: 'A4' });

// Text input
page.addTextField({
  name: 'fullName',
  x: 150,
  y: 700,
  width: 250,
  height: 24,
  font,
  fontSize: 12,
  label: 'Full Name',
});

// Checkbox
page.addCheckbox({
  name: 'agree',
  x: 150,
  y: 660,
  width: 16,
  height: 16,
  checked: false,
});

// Dropdown
page.addDropdown({
  name: 'country',
  x: 150,
  y: 620,
  width: 250,
  height: 24,
  options: ['United States', 'Canada', 'United Kingdom', 'Germany', 'France'],
  selected: 'United States',
  font,
  fontSize: 12,
});

// Radio buttons
page.addRadioGroup({
  name: 'plan',
  options: [
    { x: 150, y: 570, width: 16, height: 16, value: 'basic' },
    { x: 150, y: 545, width: 16, height: 16, value: 'pro' },
    { x: 150, y: 520, width: 16, height: 16, value: 'enterprise' },
  ],
  selected: 'basic',
});

const bytes = doc.save();
```

### Barcodes

```typescript
import { PDFDocument, drawBarcode } from 'zpdf';

const doc = PDFDocument.create();
const page = doc.addPage({ size: 'A4' });

// Code 128
drawBarcode(page, {
  type: 'code128',
  value: 'ZPDF-2024',
  x: 50,
  y: 700,
  width: 200,
  height: 60,
});

// EAN-13
drawBarcode(page, {
  type: 'ean13',
  value: '5901234123457',
  x: 50,
  y: 600,
  width: 200,
  height: 60,
});

// QR Code
drawBarcode(page, {
  type: 'qr',
  value: 'https://github.com/meszmate/zpdf',
  x: 50,
  y: 450,
  width: 120,
  height: 120,
});

// Code 39
drawBarcode(page, {
  type: 'code39',
  value: 'HELLO',
  x: 50,
  y: 350,
  width: 250,
  height: 60,
});

const bytes = doc.save();
```

### Encryption

```typescript
import { PDFDocument } from 'zpdf';

const doc = PDFDocument.create({ title: 'Confidential Report' });
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage();

page.drawText('This document is encrypted with AES-256.', {
  x: 50,
  y: 750,
  font,
  fontSize: 14,
});

doc.encrypt({
  ownerPassword: 'owner-secret',
  userPassword: 'user-pass',
  algorithm: 'aes-256',
  permissions: {
    printing: true,
    copying: false,
    modifying: false,
    annotating: false,
    fillingForms: true,
    contentAccessibility: true,
    documentAssembly: false,
    printingHighQuality: true,
  },
});

const bytes = doc.save();
```

### Merging PDFs

```typescript
import { PDFMerger } from 'zpdf';
import { readFileSync, writeFileSync } from 'node:fs';

const merger = new PDFMerger();

// Add entire documents
merger.add(readFileSync('document1.pdf'));
merger.add(readFileSync('document2.pdf'));

// Add specific pages (0-based indices)
merger.add(readFileSync('document3.pdf'), [0, 2, 4]);

const merged = await merger.merge();
writeFileSync('merged.pdf', merged);
```

### Splitting PDFs

```typescript
import { PDFSplitter } from 'zpdf';
import { readFileSync, writeFileSync } from 'node:fs';

const pdfBytes = readFileSync('large-document.pdf');

// Split into individual pages
const pages = await PDFSplitter.splitByPage(pdfBytes);
pages.forEach((page, i) => writeFileSync(`page-${i + 1}.pdf`, page));

// Split by ranges (0-based, inclusive)
const parts = await PDFSplitter.splitByRanges(pdfBytes, [
  [0, 4],   // Pages 1-5
  [5, 9],   // Pages 6-10
  [10, 14], // Pages 11-15
]);
parts.forEach((part, i) => writeFileSync(`part-${i + 1}.pdf`, part));
```

### Parsing PDFs

```typescript
import { parsePdf } from 'zpdf';
import { readFileSync } from 'node:fs';

const pdfBytes = readFileSync('existing.pdf');
const doc = await parsePdf(pdfBytes);

// Document metadata
console.log('Title:', doc.info?.title);
console.log('Author:', doc.info?.author);
console.log('Pages:', doc.pages.length);

// Extract text from each page
for (const page of doc.pages) {
  const textItems = page.extractText();
  for (const item of textItems) {
    console.log(`[${item.fontName} ${item.fontSize}pt] (${item.x}, ${item.y}): ${item.text}`);
  }
}

// Extract images
for (const page of doc.pages) {
  const images = page.extractImages();
  for (const img of images) {
    console.log(`Image: ${img.width}x${img.height}, ${img.colorSpace}, ${img.data.length} bytes`);
  }
}

// Read form fields
if (doc.formFields) {
  for (const field of doc.formFields) {
    console.log(`Field "${field.name}": ${field.value} (${field.type})`);
  }
}
```

### Watermarks

```typescript
import { addWatermark } from 'zpdf';
import { readFileSync, writeFileSync } from 'node:fs';

const pdfBytes = readFileSync('document.pdf');

const watermarked = await addWatermark(pdfBytes, {
  text: 'CONFIDENTIAL',
  fontSize: 60,
  color: { type: 'rgb', r: 1, g: 0, b: 0 },
  opacity: 0.15,
  rotation: -45,
});

writeFileSync('watermarked.pdf', watermarked);
```

### Bookmarks

```typescript
import { PDFDocument } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica-Bold');

const chapter1 = doc.addPage();
chapter1.drawText('Chapter 1: Introduction', { x: 50, y: 750, font, fontSize: 24 });

const chapter2 = doc.addPage();
chapter2.drawText('Chapter 2: Getting Started', { x: 50, y: 750, font, fontSize: 24 });

const chapter3 = doc.addPage();
chapter3.drawText('Chapter 3: Advanced Topics', { x: 50, y: 750, font, fontSize: 24 });

doc.addBookmark({ title: 'Chapter 1: Introduction', pageIndex: 0 });
doc.addBookmark({ title: 'Chapter 2: Getting Started', pageIndex: 1 });
const ch3 = doc.addBookmark({ title: 'Chapter 3: Advanced Topics', pageIndex: 2 });
doc.addBookmark({ title: '3.1 Performance', pageIndex: 2, parent: ch3 });
doc.addBookmark({ title: '3.2 Security', pageIndex: 2, parent: ch3 });

const bytes = doc.save();
```

### Annotations

```typescript
import { PDFDocument, rgb } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage();

page.drawText('Hover over the icon to see a note.', { x: 50, y: 750, font, fontSize: 12 });

// Sticky note annotation
page.addAnnotation({
  type: 'text',
  rect: { x: 50, y: 700, width: 24, height: 24 },
  contents: 'This is a sticky note comment.',
  color: rgb(255, 255, 0),
});

// Link annotation
page.addAnnotation({
  type: 'link',
  rect: { x: 50, y: 660, width: 200, height: 16 },
  uri: 'https://github.com/meszmate/zpdf',
});

// Highlight annotation
page.addAnnotation({
  type: 'highlight',
  rect: { x: 50, y: 740, width: 300, height: 16 },
  color: rgb(255, 255, 0),
});

const bytes = doc.save();
```

### Custom Paths

```typescript
import { PDFDocument, PathBuilder, rgb } from 'zpdf';

const doc = PDFDocument.create();
const page = doc.addPage();

// Draw a star using PathBuilder
const star = new PathBuilder();
const cx = 300, cy = 500, outerR = 80, innerR = 35;

for (let i = 0; i < 5; i++) {
  const outerAngle = (Math.PI / 2) + (i * 2 * Math.PI / 5);
  const innerAngle = outerAngle + Math.PI / 5;

  const ox = cx + outerR * Math.cos(outerAngle);
  const oy = cy + outerR * Math.sin(outerAngle);
  const ix = cx + innerR * Math.cos(innerAngle);
  const iy = cy + innerR * Math.sin(innerAngle);

  if (i === 0) {
    star.moveTo(ox, oy);
  } else {
    star.lineTo(ox, oy);
  }
  star.lineTo(ix, iy);
}
star.close();

page.drawPath(star, {
  color: rgb(241, 196, 15),
  borderColor: rgb(243, 156, 18),
  borderWidth: 2,
});

const bytes = doc.save();
```

### Layers (Optional Content)

```typescript
import { PDFDocument, LayerBuilder, rgb } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage();

const layers = new LayerBuilder(doc);

const englishLayer = layers.addLayer('English');
const spanishLayer = layers.addLayer('Spanish');

page.beginLayer(englishLayer);
page.drawText('Hello, World!', { x: 50, y: 700, font, fontSize: 20, color: rgb(0, 0, 0) });
page.endLayer();

page.beginLayer(spanishLayer);
page.drawText('Hola, Mundo!', { x: 50, y: 700, font, fontSize: 20, color: rgb(0, 0, 0) });
page.endLayer();

const bytes = doc.save();
```

### Tagged PDF (Accessibility)

```typescript
import { PDFDocument, StructureTree, StructureTags } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const boldFont = doc.getStandardFont('Helvetica-Bold');
const page = doc.addPage();

const structTree = new StructureTree(doc);

structTree.beginElement(StructureTags.Document);

structTree.beginElement(StructureTags.H1);
page.drawText('Accessible Document', { x: 50, y: 750, font: boldFont, fontSize: 24 });
structTree.endElement();

structTree.beginElement(StructureTags.P);
page.drawText('This document is tagged for screen readers and assistive technology.', {
  x: 50,
  y: 710,
  font,
  fontSize: 12,
  maxWidth: 500,
});
structTree.endElement();

structTree.endElement(); // Document

const bytes = doc.save();
```

---

## API Reference

### PDFDocument

The main entry point for creating PDF documents.

| Method | Description |
|--------|-------------|
| `PDFDocument.create(options?)` | Create a new empty document |
| `addPage(options?)` | Add a new page |
| `getPage(index)` | Get a page by index |
| `getPageCount()` | Return the number of pages |
| `removePage(index)` | Remove a page by index |
| `insertPage(index, options?)` | Insert a page at a specific position |
| `setTitle(title)` | Set document title |
| `setAuthor(author)` | Set document author |
| `setSubject(subject)` | Set document subject |
| `setKeywords(keywords)` | Set document keywords |
| `getStandardFont(name)` | Get one of the 14 standard fonts |
| `registerFont(data)` | Register a TrueType font |
| `embedJpeg(data)` | Embed a JPEG image |
| `embedPng(data)` | Embed a PNG image |
| `encrypt(options)` | Encrypt the document |
| `addBookmark(options)` | Add a bookmark entry |
| `save(options?)` | Serialize to `Uint8Array` |

### PDFPage

Represents a single page with drawing methods.

| Method | Description |
|--------|-------------|
| `drawText(text, options)` | Draw text with font, size, color, alignment |
| `drawRichText(runs, options)` | Draw text with mixed formatting |
| `drawRect(options)` | Draw a rectangle |
| `drawCircle(options)` | Draw a circle |
| `drawEllipse(options)` | Draw an ellipse |
| `drawLine(options)` | Draw a line |
| `drawPolygon(options)` | Draw a polygon |
| `drawPath(path, options)` | Draw a custom path |
| `drawImage(image, options)` | Draw an embedded image |
| `drawTable(table, options)` | Render a table |
| `drawWatermark(options)` | Draw a watermark on the page |
| `addTextField(options)` | Add a text input form field |
| `addCheckbox(options)` | Add a checkbox form field |
| `addRadioGroup(options)` | Add a radio button group |
| `addDropdown(options)` | Add a dropdown select |
| `addListbox(options)` | Add a listbox |
| `addButton(options)` | Add a push button |
| `addSignatureField(options)` | Add a signature field |
| `addAnnotation(annotation)` | Add an annotation |
| `beginLayer(layer)` | Begin an optional content layer |
| `endLayer()` | End the current layer |
| `getWidth()` / `getHeight()` | Get page dimensions |
| `setRotation(angle)` | Set page rotation |

### Table

Build table data for rendering on a page.

| Method | Description |
|--------|-------------|
| `new Table(style?)` | Create a table with optional style |
| `setColumnWidths(widths)` | Set column widths (number, `'auto'`, or percentage string) |
| `addHeaderRow(cells)` | Add a header row |
| `addRow(cells)` | Add a data row |

### PDFMerger

Merge multiple PDF files.

| Method | Description |
|--------|-------------|
| `add(pdfBytes, pages?)` | Add a PDF to the merge queue |
| `merge()` | Merge all queued PDFs and return `Uint8Array` |

### PDFSplitter

Split a PDF into smaller documents.

| Method | Description |
|--------|-------------|
| `PDFSplitter.splitByPage(pdfBytes)` | Split into one PDF per page |
| `PDFSplitter.splitByRanges(pdfBytes, ranges)` | Split by page ranges |

### PathBuilder

Construct custom vector paths.

| Method | Description |
|--------|-------------|
| `moveTo(x, y)` | Move the pen |
| `lineTo(x, y)` | Draw a straight line |
| `curveTo(x1, y1, x2, y2, x3, y3)` | Cubic bezier curve |
| `quadraticCurveTo(x1, y1, x2, y2)` | Quadratic bezier curve |
| `arc(cx, cy, r, ...)` | Circular arc |
| `close()` | Close the path |

### parsePdf

Parse an existing PDF document.

```typescript
const doc = await parsePdf(pdfBytes: Uint8Array, password?: string): Promise<ParsedDocument>;
```

Returns a `ParsedDocument` with:
- `info` - Document metadata (title, author, subject, etc.)
- `pages` - Array of `ParsedPage` with `extractText()` and `extractImages()`
- `outline` - Bookmark tree
- `formFields` - Array of `FormFieldInfo`

### Color Utilities

```typescript
import { rgb, cmyk, grayscale, hexColor } from 'zpdf';

rgb(255, 0, 0);           // Red (values 0-255)
cmyk(0, 100, 100, 0);     // Red in CMYK (values 0-100)
grayscale(128);            // 50% gray (values 0-255)
hexColor('#ff6600');       // From hex string
```

Color conversion functions: `rgbToCmyk`, `cmykToRgb`, `rgbToGrayscale`, `grayscaleToRgb`.

---

## Page Sizes

All sizes are in PDF points (1 point = 1/72 inch).

| Name | Width x Height (pt) | Dimensions |
|------|---------------------|------------|
| `A0` | 2384 x 3370 | 841 x 1189 mm |
| `A1` | 1684 x 2384 | 594 x 841 mm |
| `A2` | 1191 x 1684 | 420 x 594 mm |
| `A3` | 842 x 1191 | 297 x 420 mm |
| `A4` | 595 x 842 | 210 x 297 mm |
| `A5` | 420 x 595 | 148 x 210 mm |
| `A6` | 298 x 420 | 105 x 148 mm |
| `A7` | 210 x 298 | 74 x 105 mm |
| `A8` | 148 x 210 | 52 x 74 mm |
| `B0` | 2835 x 4008 | 1000 x 1414 mm |
| `B1` | 2004 x 2835 | 707 x 1000 mm |
| `B2` | 1417 x 2004 | 500 x 707 mm |
| `B3` | 1001 x 1417 | 353 x 500 mm |
| `B4` | 709 x 1001 | 250 x 353 mm |
| `B5` | 499 x 709 | 176 x 250 mm |
| `Letter` | 612 x 792 | 8.5 x 11 in |
| `Legal` | 612 x 1008 | 8.5 x 14 in |
| `Tabloid` | 792 x 1224 | 11 x 17 in |
| `Ledger` | 1224 x 792 | 17 x 11 in |
| `Executive` | 522 x 756 | 7.25 x 10.5 in |
| `Folio` | 612 x 936 | 8.5 x 13 in |
| `Quarto` | 610 x 780 | 8.5 x 10.83 in |
| `10x14` | 720 x 1008 | 10 x 14 in |
| `11x17` | 792 x 1224 | 11 x 17 in |

You can also use custom sizes by passing a `[width, height]` tuple.

---

## Standard Fonts

The 14 standard PDF fonts are available without embedding any font data:

| Font Family | Regular | Bold | Italic/Oblique | Bold Italic/Oblique |
|-------------|---------|------|----------------|---------------------|
| Helvetica | `Helvetica` | `Helvetica-Bold` | `Helvetica-Oblique` | `Helvetica-BoldOblique` |
| Times | `Times-Roman` | `Times-Bold` | `Times-Italic` | `Times-BoldItalic` |
| Courier | `Courier` | `Courier-Bold` | `Courier-Oblique` | `Courier-BoldOblique` |
| Symbol | `Symbol` | | | |
| Zapf Dingbats | `ZapfDingbats` | | | |

---

## Browser Support

zpdf is a pure TypeScript library with zero runtime dependencies. It works in any environment that supports `Uint8Array` and standard ES2020+ features:

- **Node.js** 16+
- **Deno**
- **Bun**
- **Modern browsers** (Chrome, Firefox, Safari, Edge)

The library deliberately avoids Node.js-specific APIs like `Buffer`. All binary data uses `Uint8Array` for maximum portability.

```typescript
// Browser example
import { PDFDocument } from 'zpdf';

const doc = PDFDocument.create();
const font = doc.getStandardFont('Helvetica');
const page = doc.addPage();
page.drawText('Created in the browser!', { x: 50, y: 750, font, fontSize: 16 });

const bytes = doc.save();
const blob = new Blob([bytes], { type: 'application/pdf' });
const url = URL.createObjectURL(blob);
window.open(url);
```

---

## Performance

zpdf is designed for efficiency:

- **Streaming serialization** - PDF objects are written sequentially without building the entire document in memory
- **Font subsetting** - Only glyphs actually used in the document are embedded, keeping file sizes small
- **Deflate compression** - Content streams are compressed using a built-in deflate implementation
- **Lazy parsing** - The PDF parser reads only the structures needed, avoiding full document materialization
- **No dependencies** - Zero runtime dependencies means no overhead from transitive packages

---

## Contributing

Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) before submitting a pull request.

---

## License

[MIT](LICENSE) - Copyright (c) 2026 meszmate
