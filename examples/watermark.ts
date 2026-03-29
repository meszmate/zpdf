/**
 * watermark.ts
 *
 * Demonstrates adding watermarks to PDF documents with zpdf:
 *  - Creating a sample multi-page PDF
 *  - Adding a text watermark with rotation and opacity
 *  - Customizing watermark color, font size, and position
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  addWatermark,
  rgb,
  grayscale,
} from '../src/index';

/**
 * Helper: create a multi-page sample PDF to apply watermarks to.
 */
async function createSamplePdf(): Promise<Uint8Array> {
  const doc = PDFDocument.create();
  doc.setTitle('Sample Document for Watermarking');

  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');

  // Create 3 pages with different content
  const pageContents = [
    {
      title: 'Introduction',
      body: 'This is the introduction page of the document. It contains important ' +
        'information that needs to be protected with a watermark to indicate ' +
        'its draft status or confidential nature.',
    },
    {
      title: 'Main Content',
      body: 'This page contains the main body of the document. Watermarks are ' +
        'commonly used to mark documents as DRAFT, CONFIDENTIAL, SAMPLE, ' +
        'or to indicate copyright ownership.',
    },
    {
      title: 'Conclusion',
      body: 'This is the final page. The watermark appears on every page of the ' +
        'document, ensuring that regardless of which page is printed or ' +
        'viewed, the watermark message is visible.',
    },
  ];

  for (const { title, body } of pageContents) {
    const page = doc.addPage({ size: 'A4' });
    const { width, height } = page.getSize();

    page.drawText(title, {
      x: 60,
      y: height - 80,
      font: helveticaBold,
      fontSize: 24,
      color: rgb(0, 0, 0),
    });

    page.drawLine({
      x1: 60, y1: height - 95,
      x2: width - 60, y2: height - 95,
      color: grayscale(0.7),
      lineWidth: 1,
    });

    page.drawText(body, {
      x: 60,
      y: height - 130,
      font: helvetica,
      fontSize: 12,
      color: grayscale(0.2),
      maxWidth: width - 120,
      lineHeight: 1.6,
    });

    // Add some visual elements to show watermark layering
    page.drawRect({
      x: 60, y: height - 350,
      width: width - 120, height: 150,
      color: rgb(245, 248, 252),
      borderColor: grayscale(0.8),
      borderWidth: 0.5,
    });

    page.drawText('Sample content area -- the watermark will overlay this.', {
      x: 80,
      y: height - 280,
      font: helvetica,
      fontSize: 11,
      color: grayscale(0.4),
    });
  }

  return doc.save();
}

async function main() {
  // =================================================================
  // Step 1: Create the base PDF
  // =================================================================
  console.log('Creating sample PDF...');
  const basePdf = await createSamplePdf();
  writeFileSync('output/watermark-original.pdf', basePdf);
  console.log(`  Created watermark-original.pdf (${basePdf.length} bytes, 3 pages)`);

  // =================================================================
  // Step 2: Add a "DRAFT" watermark (classic style)
  // =================================================================
  console.log('\nAdding "DRAFT" watermark...');
  const draftPdf = await addWatermark(basePdf, {
    text: 'DRAFT',
    fontSize: 72,
    color: rgb(255, 0, 0),        // Red
    opacity: 0.15,                 // Very subtle
    rotation: 45,                  // Diagonal
    position: 'center',
  });
  writeFileSync('output/watermark-draft.pdf', draftPdf);
  console.log(`  Created watermark-draft.pdf (${draftPdf.length} bytes)`);
  console.log('  Red "DRAFT" at 45 degrees, 15% opacity, centered');

  // =================================================================
  // Step 3: Add a "CONFIDENTIAL" watermark
  // =================================================================
  console.log('\nAdding "CONFIDENTIAL" watermark...');
  const confPdf = await addWatermark(basePdf, {
    text: 'CONFIDENTIAL',
    fontSize: 54,
    color: grayscale(0.5),         // Gray
    opacity: 0.2,
    rotation: 30,
    position: 'center',
  });
  writeFileSync('output/watermark-confidential.pdf', confPdf);
  console.log(`  Created watermark-confidential.pdf (${confPdf.length} bytes)`);
  console.log('  Gray "CONFIDENTIAL" at 30 degrees, 20% opacity');

  // =================================================================
  // Step 4: Add a "SAMPLE" watermark at the top
  // =================================================================
  console.log('\nAdding "SAMPLE" watermark at top...');
  const samplePdf = await addWatermark(basePdf, {
    text: 'SAMPLE',
    fontSize: 48,
    color: rgb(0, 0, 200),        // Blue
    opacity: 0.25,
    rotation: 0,                   // Horizontal
    position: 'top',
  });
  writeFileSync('output/watermark-sample-top.pdf', samplePdf);
  console.log(`  Created watermark-sample-top.pdf (${samplePdf.length} bytes)`);
  console.log('  Blue "SAMPLE" horizontal at top, 25% opacity');

  // =================================================================
  // Step 5: Add a copyright watermark at the bottom
  // =================================================================
  console.log('\nAdding copyright watermark at bottom...');
  const copyrightPdf = await addWatermark(basePdf, {
    text: '(C) 2025 zpdf Library',
    fontSize: 36,
    color: grayscale(0.6),
    opacity: 0.3,
    rotation: 0,
    position: 'bottom',
  });
  writeFileSync('output/watermark-copyright.pdf', copyrightPdf);
  console.log(`  Created watermark-copyright.pdf (${copyrightPdf.length} bytes)`);
  console.log('  Gray copyright notice at bottom, 30% opacity');

  // =================================================================
  // Step 6: Bold watermark with high opacity
  // =================================================================
  console.log('\nAdding bold "DO NOT COPY" watermark...');
  const boldPdf = await addWatermark(basePdf, {
    text: 'DO NOT COPY',
    fontSize: 80,
    color: rgb(200, 0, 0),
    opacity: 0.4,                  // More visible
    rotation: -45,                 // Opposite diagonal
    position: 'center',
  });
  writeFileSync('output/watermark-bold.pdf', boldPdf);
  console.log(`  Created watermark-bold.pdf (${boldPdf.length} bytes)`);
  console.log('  Red "DO NOT COPY" at -45 degrees, 40% opacity (very visible)');

  console.log('\nAll watermark examples saved to output/');
}

main().catch(console.error);
