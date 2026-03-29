/**
 * parse-pdf.ts
 *
 * Demonstrates PDF parsing with zpdf:
 *  - Creating a PDF with known content
 *  - Parsing it back from bytes
 *  - Reading metadata (title, author, page count)
 *  - Extracting text from pages
 *  - Inspecting page dimensions
 */

import { writeFileSync } from 'node:fs';
import { PDFDocument, rgb, parsePdf } from '../src/index.js';

async function main() {
  // Step 1: Create a sample PDF with known content
  console.log('Step 1: Creating a sample PDF...');

  const doc = PDFDocument.create();
  doc.setTitle('Parse Demo Document');
  doc.setAuthor('zpdf Library');
  doc.setSubject('Demonstrating PDF parsing');

  const font = doc.getStandardFont('Helvetica');
  const boldFont = doc.getStandardFont('Helvetica-Bold');

  // Page 1
  const page1 = doc.addPage({ size: 'A4' });
  page1.drawText('Page 1: Introduction', {
    x: 50,
    y: 750,
    font: boldFont,
    fontSize: 24,
    color: rgb(0, 0, 0),
  });
  page1.drawText('This is the first page of our test document.', {
    x: 50,
    y: 700,
    font,
    fontSize: 14,
  });

  // Page 2
  const page2 = doc.addPage({ size: 'Letter' });
  page2.drawText('Page 2: Details', {
    x: 50,
    y: 720,
    font: boldFont,
    fontSize: 24,
    color: rgb(0, 0, 0),
  });
  page2.drawText('This is the second page with Letter size.', {
    x: 50,
    y: 670,
    font,
    fontSize: 14,
  });

  // Page 3
  const page3 = doc.addPage({ size: 'A4', orientation: 'landscape' });
  page3.drawText('Page 3: Landscape', {
    x: 50,
    y: 550,
    font: boldFont,
    fontSize: 24,
    color: rgb(0, 0, 0),
  });

  const pdfBytes = await doc.save();
  writeFileSync('output-parse-source.pdf', pdfBytes);
  console.log(`  Created PDF: ${pdfBytes.length} bytes, saved to output-parse-source.pdf`);

  // Step 2: Parse the PDF back
  console.log('\nStep 2: Parsing the PDF...');

  const parsed = await parsePdf(pdfBytes);

  console.log(`  PDF Version: ${parsed.version}`);
  console.log(`  Page Count: ${parsed.pageCount}`);
  console.log(`  Encrypted: ${parsed.isEncrypted}`);

  // Step 3: Inspect pages
  console.log('\nStep 3: Page details:');

  for (let i = 0; i < parsed.pageCount; i++) {
    const page = parsed.getPage(i);
    console.log(`  Page ${i + 1}:`);
    console.log(`    MediaBox: [${page.mediaBox.join(', ')}]`);
    console.log(`    Rotation: ${page.rotation}deg`);

    const width = page.mediaBox[2] - page.mediaBox[0];
    const height = page.mediaBox[3] - page.mediaBox[1];
    console.log(`    Dimensions: ${width} x ${height} points (${(width / 72).toFixed(1)}" x ${(height / 72).toFixed(1)}")`);
  }

  // Step 4: Extract text
  console.log('\nStep 4: Text extraction:');

  for (let i = 0; i < parsed.pageCount; i++) {
    const page = parsed.getPage(i);
    try {
      const textItems = await page.extractText();
      console.log(`  Page ${i + 1} text items: ${textItems.length}`);
      for (const item of textItems) {
        console.log(`    "${item.text}" at (${item.x.toFixed(1)}, ${item.y.toFixed(1)}) size=${item.fontSize}`);
      }
    } catch (e) {
      console.log(`  Page ${i + 1}: text extraction not available (${(e as Error).message})`);
    }
  }

  console.log('\nDone! PDF parsing complete.');
}

main().catch(console.error);
