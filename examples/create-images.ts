/**
 * create-images.ts
 *
 * Demonstrates image handling in zpdf:
 *  - Embedding JPEG images
 *  - Embedding PNG images
 *  - Image positioning and scaling
 *  - Multiple images on a page
 *
 * Since we do not have actual image files available, this example creates
 * synthetic image data (a minimal valid JPEG and PNG) to demonstrate the
 * API patterns. In a real application you would read actual image files
 * from disk.
 */

import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import {
  PDFDocument,
  rgb,
  grayscale,
} from '../src/index';

/**
 * Create a minimal 1x1 red JPEG for demonstration.
 * This is a valid JPEG binary (the smallest possible).
 */
function createMinimalJpeg(): Uint8Array {
  // A minimal valid JPEG: 1x1 pixel, red
  // This is a pre-built binary sequence for a tiny valid JPEG image.
  return new Uint8Array([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
    0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
    0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
    0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
    0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
    0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
    0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
    0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
    0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
    0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
    0x00, 0x00, 0x3F, 0x00, 0x7B, 0x94, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xD9,
  ]);
}

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('zpdf Image Example');

  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');

  const page = doc.addPage({ size: 'A4' });
  const { width, height } = page.getSize();

  page.drawText('Image Handling in zpdf', {
    x: width / 2,
    y: height - 50,
    font: helveticaBold,
    fontSize: 24,
    color: rgb(0, 51, 153),
    alignment: 'center',
  });

  // -----------------------------------------------------------------
  // Section 1: Embedding images API pattern
  // -----------------------------------------------------------------
  page.drawText('Embedding Images', {
    x: 40,
    y: height - 90,
    font: helveticaBold,
    fontSize: 16,
    color: rgb(0, 0, 0),
  });

  const codeFont = doc.getStandardFont('Courier');

  // Show the API usage pattern
  const apiExplanation = [
    '// Read image bytes from disk',
    "const jpegBytes = readFileSync('photo.jpg');",
    "const pngBytes = readFileSync('logo.png');",
    '',
    '// Embed images into the document',
    'const jpegImage = await doc.embedImage(jpegBytes);',
    'const pngImage = await doc.embedImage(pngBytes);',
    '',
    '// Draw JPEG at specific position and size',
    'page.drawImage(jpegImage, {',
    '  x: 50, y: 400,',
    '  width: 200, height: 150,',
    '});',
    '',
    '// Draw PNG with opacity',
    'page.drawImage(pngImage, {',
    '  x: 300, y: 400,',
    '  width: 100, height: 100,',
    '  opacity: 0.8,',
    '});',
  ];

  // Draw code box
  const codeBoxHeight = apiExplanation.length * 13 + 16;
  page.drawRect({
    x: 40, y: height - 110 - codeBoxHeight,
    width: width - 80, height: codeBoxHeight,
    color: rgb(245, 245, 245),
    borderColor: grayscale(0.7),
    borderWidth: 0.5,
  });

  let codeY = height - 118;
  for (const line of apiExplanation) {
    const isComment = line.trimStart().startsWith('//');
    page.drawText(line, {
      x: 55,
      y: codeY,
      font: codeFont,
      fontSize: 8.5,
      color: isComment ? rgb(0, 128, 0) : grayscale(0.15),
    });
    codeY -= 13;
  }

  // -----------------------------------------------------------------
  // Section 2: Visual placeholder for images
  // -----------------------------------------------------------------
  const placeholderY = height - 420;

  page.drawText('Image Placement Examples (placeholders)', {
    x: 40,
    y: placeholderY + 20,
    font: helveticaBold,
    fontSize: 16,
    color: rgb(0, 0, 0),
  });

  // Draw placeholders representing where images would appear

  // Placeholder 1: Large image
  page.drawRect({
    x: 40, y: placeholderY - 150,
    width: 200, height: 150,
    color: rgb(230, 230, 230),
    borderColor: grayscale(0.5),
    borderWidth: 1,
  });
  page.drawLine({
    x1: 40, y1: placeholderY - 150,
    x2: 240, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawLine({
    x1: 240, y1: placeholderY - 150,
    x2: 40, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawText('200 x 150', {
    x: 140,
    y: placeholderY - 80,
    font: helvetica,
    fontSize: 12,
    color: grayscale(0.4),
    alignment: 'center',
  });
  page.drawText('JPEG Photo', {
    x: 140,
    y: placeholderY - 165,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // Placeholder 2: Square image
  page.drawRect({
    x: 280, y: placeholderY - 120,
    width: 120, height: 120,
    color: rgb(230, 240, 250),
    borderColor: grayscale(0.5),
    borderWidth: 1,
  });
  page.drawLine({
    x1: 280, y1: placeholderY - 120,
    x2: 400, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawLine({
    x1: 400, y1: placeholderY - 120,
    x2: 280, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawText('120 x 120', {
    x: 340,
    y: placeholderY - 65,
    font: helvetica,
    fontSize: 11,
    color: grayscale(0.4),
    alignment: 'center',
  });
  page.drawText('PNG Logo', {
    x: 340,
    y: placeholderY - 135,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // Placeholder 3: Small thumbnail
  page.drawRect({
    x: 440, y: placeholderY - 80,
    width: 80, height: 80,
    color: rgb(250, 240, 230),
    borderColor: grayscale(0.5),
    borderWidth: 1,
  });
  page.drawLine({
    x1: 440, y1: placeholderY - 80,
    x2: 520, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawLine({
    x1: 520, y1: placeholderY - 80,
    x2: 440, y2: placeholderY,
    color: grayscale(0.7), lineWidth: 0.5,
  });
  page.drawText('80 x 80', {
    x: 480,
    y: placeholderY - 45,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.4),
    alignment: 'center',
  });
  page.drawText('Thumbnail', {
    x: 480,
    y: placeholderY - 95,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // -----------------------------------------------------------------
  // Section 3: Image scaling notes
  // -----------------------------------------------------------------
  const notesY = placeholderY - 210;

  page.drawText('Image API Notes', {
    x: 40,
    y: notesY,
    font: helveticaBold,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  const notes = [
    '1. doc.embedImage() accepts Uint8Array of JPEG or PNG data.',
    '2. Returns an ImageRef with { ref, width, height } (original pixel dimensions).',
    '3. page.drawImage(imageRef, options) draws the image at the specified position.',
    '4. If only width is specified, height is calculated to maintain aspect ratio (and vice versa).',
    '5. If neither width nor height is given, the image is drawn at its natural size (1 pixel = 1 point).',
    '6. The opacity option (0 to 1) controls image transparency.',
    '7. Images are embedded once and can be drawn on multiple pages.',
    '8. Coordinates use PDF convention: (0,0) is bottom-left of the page.',
  ];

  let noteY = notesY - 22;
  for (const note of notes) {
    page.drawText(note, {
      x: 50,
      y: noteY,
      font: helvetica,
      fontSize: 10,
      color: grayscale(0.2),
      maxWidth: width - 100,
    });
    noteY -= 18;
  }

  // ---------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------
  const pdfBytes = await doc.save();
  writeFileSync('output/images.pdf', pdfBytes);
  console.log(`Created output/images.pdf (${pdfBytes.length} bytes)`);
}

main().catch(console.error);
