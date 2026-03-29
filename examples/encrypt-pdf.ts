/**
 * encrypt-pdf.ts
 *
 * Demonstrates PDF security and encryption with zpdf:
 *  - Creating a PDF with content
 *  - Encrypting with different algorithms (RC4-40, RC4-128, AES-128, AES-256)
 *  - Setting permissions (no printing, no copying, etc.)
 *  - Password protection (owner + user passwords)
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  rgb,
  grayscale,
} from '../src/index';

/**
 * Helper: create a sample PDF with some content to encrypt.
 */
function createSampleDocument(title: string): PDFDocument {
  const doc = PDFDocument.create();
  doc.setTitle(title);
  doc.setAuthor('zpdf Library');

  const helveticaBold = doc.getStandardFont('Helvetica-Bold');
  const helvetica = doc.getStandardFont('Helvetica');

  const page = doc.addPage({ size: 'A4' });
  const { width, height } = page.getSize();

  // Header
  page.drawRect({
    x: 0, y: height - 70, width, height: 70,
    color: rgb(40, 40, 40),
  });
  page.drawText(title, {
    x: width / 2,
    y: height - 42,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(255, 255, 255),
    alignment: 'center',
  });

  // Content
  page.drawText('Confidential Document', {
    x: width / 2,
    y: height - 120,
    font: helveticaBold,
    fontSize: 16,
    color: rgb(200, 0, 0),
    alignment: 'center',
  });

  page.drawText(
    'This document contains sensitive information that is protected by ' +
    'PDF encryption. The encryption settings control who can open the ' +
    'document and what operations (printing, copying, editing) are allowed.',
    {
      x: 60,
      y: height - 170,
      font: helvetica,
      fontSize: 11,
      color: grayscale(0.2),
      maxWidth: width - 120,
      lineHeight: 1.5,
    },
  );

  // Add a "sensitive" table-like section
  const dataY = height - 260;
  page.drawRect({
    x: 60, y: dataY - 120, width: width - 120, height: 130,
    color: rgb(250, 245, 240),
    borderColor: grayscale(0.7),
    borderWidth: 0.5,
  });

  const fields = [
    ['Account Number:', 'XXXX-XXXX-1234'],
    ['Balance:', '$45,678.90'],
    ['Status:', 'Active'],
    ['Last Transaction:', '2025-03-15'],
  ];

  let fieldY = dataY;
  for (const [label, value] of fields) {
    page.drawText(label, {
      x: 80,
      y: fieldY,
      font: helveticaBold,
      fontSize: 11,
      color: grayscale(0.3),
    });
    page.drawText(value, {
      x: 240,
      y: fieldY,
      font: helvetica,
      fontSize: 11,
      color: grayscale(0.1),
    });
    fieldY -= 25;
  }

  return doc;
}

async function main() {
  // =================================================================
  // 1. RC4-40 encryption (weakest, PDF 1.1 compatible)
  // =================================================================
  console.log('Creating RC4-40 encrypted PDF...');
  const doc1 = createSampleDocument('RC4-40 Encrypted Document');
  doc1.encrypt({
    ownerPassword: 'owner-secret',
    userPassword: 'user-pass',
    algorithm: 'rc4-40',
    permissions: {
      printing: true,
      copying: true,
      modifying: true,
      annotating: true,
    },
  });
  const pdf1 = await doc1.save();
  writeFileSync('output/encrypted-rc4-40.pdf', pdf1);
  console.log(`  Created encrypted-rc4-40.pdf (${pdf1.length} bytes)`);
  console.log('  Owner password: "owner-secret", User password: "user-pass"');
  console.log('  All permissions granted');

  // =================================================================
  // 2. RC4-128 encryption (standard)
  // =================================================================
  console.log('\nCreating RC4-128 encrypted PDF...');
  const doc2 = createSampleDocument('RC4-128 Encrypted Document');
  doc2.encrypt({
    ownerPassword: 'strong-owner-pw',
    userPassword: 'user123',
    algorithm: 'rc4-128',
    permissions: {
      printing: true,
      copying: false,     // No copying
      modifying: false,   // No modifying
      annotating: true,
    },
  });
  const pdf2 = await doc2.save();
  writeFileSync('output/encrypted-rc4-128.pdf', pdf2);
  console.log(`  Created encrypted-rc4-128.pdf (${pdf2.length} bytes)`);
  console.log('  Owner password: "strong-owner-pw", User password: "user123"');
  console.log('  Printing: yes, Copying: no, Modifying: no');

  // =================================================================
  // 3. AES-128 encryption (recommended for most uses)
  // =================================================================
  console.log('\nCreating AES-128 encrypted PDF...');
  const doc3 = createSampleDocument('AES-128 Encrypted Document');
  doc3.encrypt({
    ownerPassword: 'aes-owner-2025',
    userPassword: 'reader',
    algorithm: 'aes-128',
    permissions: {
      printing: false,            // No printing
      copying: false,             // No copying
      modifying: false,           // No modifying
      annotating: false,          // No annotations
      fillingForms: true,         // Forms can be filled
      contentAccessibility: true, // Accessibility tools can access
    },
  });
  const pdf3 = await doc3.save();
  writeFileSync('output/encrypted-aes-128.pdf', pdf3);
  console.log(`  Created encrypted-aes-128.pdf (${pdf3.length} bytes)`);
  console.log('  Owner password: "aes-owner-2025", User password: "reader"');
  console.log('  Only form filling and accessibility allowed');

  // =================================================================
  // 4. AES-256 encryption (strongest, PDF 2.0)
  // =================================================================
  console.log('\nCreating AES-256 encrypted PDF...');
  const doc4 = createSampleDocument('AES-256 Encrypted Document');
  doc4.encrypt({
    ownerPassword: 'ultra-secure-owner',
    userPassword: 'aes256-user',
    algorithm: 'aes-256',
    permissions: {
      printing: false,
      printingHighQuality: false,
      copying: false,
      modifying: false,
      annotating: false,
      fillingForms: false,
      contentAccessibility: false,
      documentAssembly: false,
    },
  });
  const pdf4 = await doc4.save();
  writeFileSync('output/encrypted-aes-256.pdf', pdf4);
  console.log(`  Created encrypted-aes-256.pdf (${pdf4.length} bytes)`);
  console.log('  Owner password: "ultra-secure-owner", User password: "aes256-user"');
  console.log('  No permissions granted (view only)');

  // =================================================================
  // 5. Owner-only password (no user password required to open)
  // =================================================================
  console.log('\nCreating owner-only password PDF...');
  const doc5 = createSampleDocument('Owner-Only Password Document');
  doc5.encrypt({
    ownerPassword: 'admin-only',
    // No userPassword -- anyone can open it, but the owner password
    // is required to change permissions or remove encryption.
    algorithm: 'aes-128',
    permissions: {
      printing: true,
      copying: false,
      modifying: false,
    },
  });
  const pdf5 = await doc5.save();
  writeFileSync('output/encrypted-owner-only.pdf', pdf5);
  console.log(`  Created encrypted-owner-only.pdf (${pdf5.length} bytes)`);
  console.log('  Owner password: "admin-only", No user password needed to open');
  console.log('  Printing allowed, copying and modifying restricted');

  // =================================================================
  // Summary
  // =================================================================
  console.log('\n--- Encryption Summary ---');
  console.log('Algorithm   | Key Length | Security Level');
  console.log('------------|------------|---------------');
  console.log('RC4-40      | 40-bit     | Low (legacy)');
  console.log('RC4-128     | 128-bit    | Medium');
  console.log('AES-128     | 128-bit    | High (recommended)');
  console.log('AES-256     | 256-bit    | Highest (PDF 2.0)');
  console.log('\nAll encrypted PDFs saved to output/');
}

main().catch(console.error);
