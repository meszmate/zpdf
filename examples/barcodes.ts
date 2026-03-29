/**
 * barcodes.ts
 *
 * Demonstrates barcode generation with zpdf:
 *  - Code 128 barcode
 *  - Code 39 barcode
 *  - EAN-13 barcode
 *  - QR code
 *  - Different sizes and positions
 */

import { writeFileSync } from 'node:fs';
import { PDFDocument, rgb, grayscale } from '../src/index.js';

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('Barcode Examples');

  const page = doc.addPage({ size: 'A4' });
  const font = doc.getStandardFont('Helvetica');
  const boldFont = doc.getStandardFont('Helvetica-Bold');

  // Title
  page.drawText('Barcode Examples', {
    x: 50,
    y: 780,
    font: boldFont,
    fontSize: 28,
    color: rgb(0, 0, 0),
  });

  // --- Code 128 ---
  page.drawText('Code 128', {
    x: 50,
    y: 700,
    font: boldFont,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  page.drawBarcode('code128', 'ZPDF-LIB-2026', {
    x: 50,
    y: 630,
    width: 250,
    height: 60,
  });

  page.drawText('ZPDF-LIB-2026', {
    x: 120,
    y: 615,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // --- Code 39 ---
  page.drawText('Code 39', {
    x: 50,
    y: 570,
    font: boldFont,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  page.drawBarcode('code39', 'HELLO', {
    x: 50,
    y: 500,
    width: 250,
    height: 60,
  });

  page.drawText('HELLO', {
    x: 140,
    y: 485,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // --- EAN-13 ---
  page.drawText('EAN-13', {
    x: 50,
    y: 440,
    font: boldFont,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  page.drawBarcode('ean13', '978020137962', {
    x: 50,
    y: 370,
    width: 200,
    height: 60,
  });

  page.drawText('978-0-201-37962-? (ISBN)', {
    x: 50,
    y: 355,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // --- QR Codes ---
  page.drawText('QR Codes', {
    x: 50,
    y: 300,
    font: boldFont,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  // Simple text QR
  page.drawBarcode('qr', 'https://github.com/meszmate/zpdf', {
    x: 50,
    y: 160,
    width: 120,
    height: 120,
  });

  page.drawText('URL', {
    x: 85,
    y: 148,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // Larger QR with different data
  page.drawBarcode('qr', 'zpdf: A comprehensive PDF library for TypeScript', {
    x: 200,
    y: 160,
    width: 120,
    height: 120,
    errorLevel: 'H',
  });

  page.drawText('Text (High EC)', {
    x: 218,
    y: 148,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // Colored QR
  page.drawBarcode('qr', '12345678', {
    x: 370,
    y: 160,
    width: 120,
    height: 120,
    color: rgb(0, 100, 180),
  });

  page.drawText('Colored Numeric', {
    x: 380,
    y: 148,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  // Right side: second set of 1D barcodes
  page.drawText('More Code 128', {
    x: 340,
    y: 700,
    font: boldFont,
    fontSize: 14,
    color: rgb(0, 0, 0),
  });

  page.drawBarcode('code128', '1234567890', {
    x: 340,
    y: 630,
    width: 200,
    height: 60,
    color: rgb(0, 0, 150),
  });

  page.drawText('Numeric (colored)', {
    x: 380,
    y: 615,
    font,
    fontSize: 10,
    color: grayscale(0.3),
  });

  const bytes = await doc.save();
  writeFileSync('output-barcodes.pdf', bytes);
  console.log('Created output-barcodes.pdf');
}

main().catch(console.error);
