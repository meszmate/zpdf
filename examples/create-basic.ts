/**
 * create-basic.ts
 *
 * Demonstrates fundamental PDF creation with zpdf:
 *  - Creating a document with metadata
 *  - Adding pages with different sizes
 *  - Drawing text with multiple standard fonts
 *  - Text styling (size, color, alignment)
 *  - Word wrapping with maxWidth
 *  - Page numbers in footers
 *  - Saving to a file
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  PageSizes,
  rgb,
  hexColor,
  grayscale,
} from '../src/index';

async function main() {
  // ---------------------------------------------------------------
  // 1. Create a new document and set metadata
  // ---------------------------------------------------------------
  const doc = PDFDocument.create();

  doc.setTitle('zpdf Basic Example');
  doc.setAuthor('zpdf Library');
  doc.setSubject('Demonstrating basic PDF creation features');
  doc.setKeywords(['zpdf', 'example', 'basic', 'typescript']);
  doc.setCreator('zpdf examples');
  doc.setProducer('zpdf');

  // ---------------------------------------------------------------
  // 2. Load standard fonts
  // ---------------------------------------------------------------
  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');
  const helveticaOblique = doc.getStandardFont('Helvetica-Oblique');
  const timesRoman = doc.getStandardFont('Times-Roman');
  const timesBold = doc.getStandardFont('Times-Bold');
  const timesItalic = doc.getStandardFont('Times-Italic');
  const courier = doc.getStandardFont('Courier');
  const courierBold = doc.getStandardFont('Courier-Bold');

  // ---------------------------------------------------------------
  // 3. Page 1 -- Title page (A4, portrait)
  // ---------------------------------------------------------------
  const page1 = doc.addPage({ size: 'A4' });
  const { width: p1w, height: p1h } = page1.getSize();

  // Large centered title
  page1.drawText('zpdf Library', {
    x: p1w / 2,
    y: p1h - 200,
    font: helveticaBold,
    fontSize: 36,
    color: rgb(0, 51, 153),
    alignment: 'center',
  });

  // Subtitle
  page1.drawText('Basic PDF Creation Example', {
    x: p1w / 2,
    y: p1h - 250,
    font: helveticaOblique,
    fontSize: 18,
    color: grayscale(0.4),
    alignment: 'center',
  });

  // Decorative horizontal rule
  page1.drawLine({
    x1: 100,
    y1: p1h - 280,
    x2: p1w - 100,
    y2: p1h - 280,
    color: rgb(0, 51, 153),
    lineWidth: 2,
  });

  // Description paragraph with word wrapping
  const description =
    'This document demonstrates the basic features of the zpdf library. ' +
    'It shows how to create pages, draw text with various fonts and styles, ' +
    'use colors, align text, and add page footers. The library is a pure ' +
    'TypeScript solution with zero dependencies.';

  page1.drawText(description, {
    x: 80,
    y: p1h - 320,
    font: timesRoman,
    fontSize: 13,
    color: grayscale(0.2),
    maxWidth: p1w - 160,
    lineHeight: 1.5,
  });

  // Footer with page number
  page1.drawText('Page 1', {
    x: p1w / 2,
    y: 40,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // ---------------------------------------------------------------
  // 4. Page 2 -- Font showcase (A4, portrait)
  // ---------------------------------------------------------------
  const page2 = doc.addPage({ size: 'A4' });
  const { width: p2w, height: p2h } = page2.getSize();

  page2.drawText('Font Showcase', {
    x: 60,
    y: p2h - 60,
    font: helveticaBold,
    fontSize: 24,
    color: rgb(0, 0, 0),
  });

  // Draw a sample of each available font
  const fonts = [
    { font: helvetica, label: 'Helvetica' },
    { font: helveticaBold, label: 'Helvetica-Bold' },
    { font: helveticaOblique, label: 'Helvetica-Oblique' },
    { font: timesRoman, label: 'Times-Roman' },
    { font: timesBold, label: 'Times-Bold' },
    { font: timesItalic, label: 'Times-Italic' },
    { font: courier, label: 'Courier' },
    { font: courierBold, label: 'Courier-Bold' },
  ];

  let yPos = p2h - 110;
  for (const { font, label } of fonts) {
    // Font name label in small gray text
    page2.drawText(label, {
      x: 60,
      y: yPos,
      font: helvetica,
      fontSize: 10,
      color: grayscale(0.5),
    });

    // Sample text in the actual font
    page2.drawText('The quick brown fox jumps over the lazy dog', {
      x: 220,
      y: yPos,
      font,
      fontSize: 14,
      color: rgb(0, 0, 0),
    });

    yPos -= 35;
  }

  // ---------------------------------------------------------------
  // 5. Text size and color variations
  // ---------------------------------------------------------------
  yPos -= 20;
  page2.drawText('Text Sizes', {
    x: 60,
    y: yPos,
    font: helveticaBold,
    fontSize: 18,
    color: rgb(0, 0, 0),
  });

  yPos -= 30;
  const sizes = [8, 10, 12, 14, 18, 24];
  for (const size of sizes) {
    page2.drawText(`${size}pt text`, {
      x: 60,
      y: yPos,
      font: helvetica,
      fontSize: size,
      color: rgb(0, 0, 0),
    });
    yPos -= size + 10;
  }

  // Color samples
  yPos -= 20;
  page2.drawText('Color Samples', {
    x: 60,
    y: yPos,
    font: helveticaBold,
    fontSize: 18,
    color: rgb(0, 0, 0),
  });

  yPos -= 30;
  const colors = [
    { color: rgb(255, 0, 0), label: 'rgb(255, 0, 0) - Red' },
    { color: rgb(0, 128, 0), label: 'rgb(0, 128, 0) - Green' },
    { color: rgb(0, 0, 255), label: 'rgb(0, 0, 255) - Blue' },
    { color: hexColor('#FF6600'), label: "hexColor('#FF6600') - Orange" },
    { color: hexColor('#9933CC'), label: "hexColor('#9933CC') - Purple" },
    { color: grayscale(0.5), label: 'grayscale(0.5) - Gray' },
  ];

  for (const { color, label } of colors) {
    page2.drawText(label, {
      x: 60,
      y: yPos,
      font: helvetica,
      fontSize: 12,
      color,
    });
    yPos -= 22;
  }

  // Footer
  page2.drawText('Page 2', {
    x: p2w / 2,
    y: 40,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // ---------------------------------------------------------------
  // 6. Page 3 -- Text alignment and wrapping (Letter size)
  // ---------------------------------------------------------------
  const page3 = doc.addPage({ size: 'Letter' });
  const { width: p3w, height: p3h } = page3.getSize();

  page3.drawText('Text Alignment and Wrapping', {
    x: 60,
    y: p3h - 60,
    font: helveticaBold,
    fontSize: 24,
    color: rgb(0, 0, 0),
  });

  const sampleText =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do ' +
    'eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ' +
    'ad minim veniam, quis nostrud exercitation ullamco laboris.';

  // Left aligned (default)
  yPos = p3h - 110;
  page3.drawText('Left Aligned:', {
    x: 60,
    y: yPos,
    font: helveticaBold,
    fontSize: 12,
    color: grayscale(0.3),
  });
  yPos -= 20;
  page3.drawText(sampleText, {
    x: 60,
    y: yPos,
    font: timesRoman,
    fontSize: 11,
    color: rgb(0, 0, 0),
    maxWidth: p3w - 120,
    alignment: 'left',
    lineHeight: 1.4,
  });

  // Center aligned
  yPos -= 80;
  page3.drawText('Center Aligned:', {
    x: 60,
    y: yPos,
    font: helveticaBold,
    fontSize: 12,
    color: grayscale(0.3),
  });
  yPos -= 20;
  page3.drawText(sampleText, {
    x: p3w / 2,
    y: yPos,
    font: timesRoman,
    fontSize: 11,
    color: rgb(0, 0, 0),
    maxWidth: p3w - 120,
    alignment: 'center',
    lineHeight: 1.4,
  });

  // Right aligned
  yPos -= 80;
  page3.drawText('Right Aligned:', {
    x: 60,
    y: yPos,
    font: helveticaBold,
    fontSize: 12,
    color: grayscale(0.3),
  });
  yPos -= 20;
  page3.drawText(sampleText, {
    x: p3w - 60,
    y: yPos,
    font: timesRoman,
    fontSize: 11,
    color: rgb(0, 0, 0),
    maxWidth: p3w - 120,
    alignment: 'right',
    lineHeight: 1.4,
  });

  // Footer
  page3.drawText('Page 3', {
    x: p3w / 2,
    y: 40,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // ---------------------------------------------------------------
  // 7. Page 4 -- Landscape orientation (A4)
  // ---------------------------------------------------------------
  const page4 = doc.addPage({ size: 'A4', orientation: 'landscape' });
  const { width: p4w, height: p4h } = page4.getSize();

  page4.drawText('Landscape Page (A4)', {
    x: p4w / 2,
    y: p4h - 60,
    font: helveticaBold,
    fontSize: 28,
    color: rgb(0, 51, 153),
    alignment: 'center',
  });

  page4.drawText(
    `This page is ${p4w}pt wide and ${p4h}pt tall (A4 in landscape orientation).`,
    {
      x: p4w / 2,
      y: p4h - 100,
      font: helvetica,
      fontSize: 14,
      color: grayscale(0.3),
      alignment: 'center',
    },
  );

  // Footer
  page4.drawText('Page 4', {
    x: p4w / 2,
    y: 40,
    font: helvetica,
    fontSize: 10,
    color: grayscale(0.5),
    alignment: 'center',
  });

  // ---------------------------------------------------------------
  // 8. Save the document
  // ---------------------------------------------------------------
  const pdfBytes = await doc.save();
  writeFileSync('output/basic.pdf', pdfBytes);
  console.log(`Created output/basic.pdf (${pdfBytes.length} bytes, ${doc.getPageCount()} pages)`);
}

main().catch(console.error);
