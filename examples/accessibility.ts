/**
 * accessibility.ts
 *
 * Demonstrates tagged PDF / accessibility features with zpdf:
 *  - Document structure tags (headings, paragraphs)
 *  - Tagged content in content streams
 *  - Alt text concepts for images
 *  - Document language setting
 */

import { writeFileSync } from 'node:fs';
import { PDFDocument, rgb, grayscale } from '../src/index.js';

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('Accessible Document Example');
  doc.setAuthor('zpdf Library');

  const font = doc.getStandardFont('Helvetica');
  const boldFont = doc.getStandardFont('Helvetica-Bold');

  const page = doc.addPage({ size: 'A4' });

  // Use tagged content to create an accessible structure
  // Each beginTag/endTag pair wraps content with a structure tag

  // Document heading
  page.beginTag('H1', 0);
  page.drawText('Accessible PDF Document', {
    x: 50,
    y: 760,
    font: boldFont,
    fontSize: 28,
    color: rgb(0, 0, 100),
  });
  page.endTag();

  // Introduction paragraph
  page.beginTag('P', 1);
  page.drawText(
    'This document demonstrates how zpdf can create tagged PDFs for accessibility. ' +
    'Tagged PDFs include structural information that screen readers and assistive ' +
    'technologies can use to navigate and read the document content.',
    {
      x: 50,
      y: 710,
      font,
      fontSize: 12,
      color: rgb(0, 0, 0),
      maxWidth: 500,
    },
  );
  page.endTag();

  // Section heading
  page.beginTag('H2', 2);
  page.drawText('1. Document Structure', {
    x: 50,
    y: 630,
    font: boldFont,
    fontSize: 20,
    color: rgb(0, 0, 80),
  });
  page.endTag();

  page.beginTag('P', 3);
  page.drawText(
    'PDF/A and PDF/UA standards require documents to be tagged with a structure tree. ' +
    'Each piece of content is associated with a tag like H1, P, Table, Figure, etc.',
    {
      x: 50,
      y: 600,
      font,
      fontSize: 12,
      maxWidth: 500,
    },
  );
  page.endTag();

  // Another section
  page.beginTag('H2', 4);
  page.drawText('2. Figure with Alt Text', {
    x: 50,
    y: 530,
    font: boldFont,
    fontSize: 20,
    color: rgb(0, 0, 80),
  });
  page.endTag();

  page.beginTag('P', 5);
  page.drawText(
    'Images and figures should include alternative text descriptions. ' +
    'Below is a simple shape that represents a figure placeholder:',
    {
      x: 50,
      y: 500,
      font,
      fontSize: 12,
      maxWidth: 500,
    },
  );
  page.endTag();

  // Draw a placeholder "figure" with a border
  page.beginTag('Figure', 6);
  page.drawRect({
    x: 50,
    y: 380,
    width: 200,
    height: 80,
    borderColor: grayscale(0.5),
    borderWidth: 1,
    color: rgb(240, 240, 255),
  });
  page.drawText('[Figure: Chart showing growth data]', {
    x: 60,
    y: 420,
    font,
    fontSize: 10,
    color: grayscale(0.4),
  });
  page.endTag();

  // List section
  page.beginTag('H2', 7);
  page.drawText('3. Lists', {
    x: 50,
    y: 350,
    font: boldFont,
    fontSize: 20,
    color: rgb(0, 0, 80),
  });
  page.endTag();

  const listItems = [
    'Use semantic tags for all content',
    'Provide alt text for images and figures',
    'Set document language and title',
    'Use proper heading hierarchy (H1, H2, H3...)',
    'Ensure reading order matches visual order',
  ];

  let listY = 320;
  listItems.forEach((item, index) => {
    page.beginTag('LI', 8 + index);
    page.drawText(`  ${index + 1}. ${item}`, {
      x: 60,
      y: listY,
      font,
      fontSize: 12,
    });
    page.endTag();
    listY -= 20;
  });

  // Conclusion
  page.beginTag('H2', 8 + listItems.length);
  page.drawText('4. Summary', {
    x: 50,
    y: listY - 20,
    font: boldFont,
    fontSize: 20,
    color: rgb(0, 0, 80),
  });
  page.endTag();

  page.beginTag('P', 9 + listItems.length);
  page.drawText(
    'By using zpdf\'s tagging APIs, you can create documents that meet PDF/A and PDF/UA ' +
    'accessibility standards. This ensures your PDFs are usable by everyone, including ' +
    'those who rely on assistive technologies.',
    {
      x: 50,
      y: listY - 50,
      font,
      fontSize: 12,
      maxWidth: 500,
    },
  );
  page.endTag();

  const bytes = await doc.save();
  writeFileSync('output-accessibility.pdf', bytes);
  console.log('Created output-accessibility.pdf');
}

main().catch(console.error);
