/**
 * merge-pdfs.ts
 *
 * Demonstrates PDF manipulation with zpdf:
 *  - Creating sample PDF documents
 *  - Merging multiple PDFs together
 *  - Splitting a PDF into individual pages
 *  - Extracting specific pages from a PDF
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  PDFMerger,
  PDFSplitter,
  rgb,
  grayscale,
} from '../src/index';

/**
 * Helper: create a simple sample PDF with a given title and color theme.
 * Each PDF has 2 pages so we can demonstrate page-level operations.
 */
async function createSamplePdf(
  title: string,
  color: ReturnType<typeof rgb>,
  pageCount: number,
): Promise<Uint8Array> {
  const doc = PDFDocument.create();
  doc.setTitle(title);

  const font = doc.getStandardFont('Helvetica-Bold');
  const bodyFont = doc.getStandardFont('Helvetica');

  for (let i = 0; i < pageCount; i++) {
    const page = doc.addPage({ size: 'A4' });
    const { width, height } = page.getSize();

    // Colored header bar
    page.drawRect({
      x: 0, y: height - 60,
      width, height: 60,
      color,
    });

    // Title in header
    page.drawText(title, {
      x: width / 2,
      y: height - 38,
      font,
      fontSize: 20,
      color: rgb(255, 255, 255),
      alignment: 'center',
    });

    // Page indicator
    page.drawText(`Page ${i + 1} of ${pageCount}`, {
      x: width / 2,
      y: height - 100,
      font: bodyFont,
      fontSize: 14,
      color: grayscale(0.3),
      alignment: 'center',
    });

    // Some body content
    page.drawText(
      `This is page ${i + 1} from the document "${title}". ` +
      'It contains sample content for testing merge and split operations.',
      {
        x: 60,
        y: height - 150,
        font: bodyFont,
        fontSize: 11,
        color: grayscale(0.2),
        maxWidth: width - 120,
        lineHeight: 1.5,
      },
    );

    // Footer
    page.drawText(`${title} - Page ${i + 1}`, {
      x: width / 2,
      y: 30,
      font: bodyFont,
      fontSize: 9,
      color: grayscale(0.5),
      alignment: 'center',
    });
  }

  return doc.save();
}

async function main() {
  // =================================================================
  // Step 1: Create sample PDFs
  // =================================================================
  console.log('Creating sample PDFs...');

  const pdf1 = await createSamplePdf('Document Alpha', rgb(0, 100, 180), 2);
  const pdf2 = await createSamplePdf('Document Beta', rgb(180, 50, 0), 3);
  const pdf3 = await createSamplePdf('Document Gamma', rgb(0, 130, 60), 2);

  writeFileSync('output/sample-alpha.pdf', pdf1);
  writeFileSync('output/sample-beta.pdf', pdf2);
  writeFileSync('output/sample-gamma.pdf', pdf3);
  console.log(`  Created sample-alpha.pdf (${pdf1.length} bytes, 2 pages)`);
  console.log(`  Created sample-beta.pdf (${pdf2.length} bytes, 3 pages)`);
  console.log(`  Created sample-gamma.pdf (${pdf3.length} bytes, 2 pages)`);

  // =================================================================
  // Step 2: Merge all three PDFs into one
  // =================================================================
  console.log('\nMerging all PDFs...');

  const merger = new PDFMerger();
  merger.add(pdf1);   // All pages from Alpha (2 pages)
  merger.add(pdf2);   // All pages from Beta (3 pages)
  merger.add(pdf3);   // All pages from Gamma (2 pages)

  const mergedPdf = await merger.merge();
  writeFileSync('output/merged-all.pdf', mergedPdf);
  console.log(`  Created merged-all.pdf (${mergedPdf.length} bytes, expected 7 pages)`);

  // =================================================================
  // Step 3: Merge with selective pages
  // =================================================================
  console.log('\nMerging selective pages...');

  const selectiveMerger = new PDFMerger();
  selectiveMerger.add(pdf1, [0]);      // Only page 1 from Alpha
  selectiveMerger.add(pdf2, [0, 2]);   // Pages 1 and 3 from Beta
  selectiveMerger.add(pdf3, [1]);      // Only page 2 from Gamma

  const selectiveMerged = await selectiveMerger.merge();
  writeFileSync('output/merged-selective.pdf', selectiveMerged);
  console.log(`  Created merged-selective.pdf (${selectiveMerged.length} bytes, expected 4 pages)`);

  // =================================================================
  // Step 4: Split a PDF into individual pages
  // =================================================================
  console.log('\nSplitting Beta PDF into individual pages...');

  const splitPages = await PDFSplitter.splitByPage(pdf2);
  for (let i = 0; i < splitPages.length; i++) {
    writeFileSync(`output/beta-page-${i + 1}.pdf`, splitPages[i]);
    console.log(`  Created beta-page-${i + 1}.pdf (${splitPages[i].length} bytes)`);
  }

  // =================================================================
  // Step 5: Split by page ranges
  // =================================================================
  console.log('\nSplitting merged PDF by ranges...');

  const rangedSplits = await PDFSplitter.splitByRanges(mergedPdf, [
    [0, 1],   // First two pages (from Alpha)
    [2, 4],   // Pages 3-5 (from Beta)
    [5, 6],   // Last two pages (from Gamma)
  ]);

  writeFileSync('output/range-alpha.pdf', rangedSplits[0]);
  writeFileSync('output/range-beta.pdf', rangedSplits[1]);
  writeFileSync('output/range-gamma.pdf', rangedSplits[2]);
  console.log(`  Created range-alpha.pdf (${rangedSplits[0].length} bytes, 2 pages)`);
  console.log(`  Created range-beta.pdf (${rangedSplits[1].length} bytes, 3 pages)`);
  console.log(`  Created range-gamma.pdf (${rangedSplits[2].length} bytes, 2 pages)`);

  // =================================================================
  // Step 6: Extract specific pages
  // =================================================================
  console.log('\nExtracting specific pages from merged PDF...');

  const extracted = await PDFSplitter.extractPages(mergedPdf, [0, 3, 6]);
  writeFileSync('output/extracted-pages.pdf', extracted);
  console.log(`  Created extracted-pages.pdf (${extracted.length} bytes, 3 pages: first, middle, last)`);

  console.log('\nAll merge/split operations complete!');
}

main().catch(console.error);
