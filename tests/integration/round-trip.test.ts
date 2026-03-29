import { describe, it, expect } from 'vitest';
import { PDFDocument } from '../../src/document/pdf-document.js';
import { Tokenizer, TokenType } from '../../src/parser/tokenizer.js';

describe('integration: create PDF and verify structure', () => {
  it('creates a minimal PDF with valid structure', async () => {
    const doc = PDFDocument.create();
    doc.setTitle('Integration Test');
    doc.addPage();

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);

    // Verify PDF header
    expect(text.startsWith('%PDF-')).toBe(true);

    // Verify it ends with %%EOF
    expect(text.trimEnd().endsWith('%%EOF')).toBe(true);

    // Verify essential structures
    expect(text).toContain('/Type /Catalog');
    expect(text).toContain('/Type /Pages');
    expect(text).toContain('/Type /Page');
    expect(text).toContain('xref');
    expect(text).toContain('trailer');
    expect(text).toContain('startxref');
  });

  it('creates a PDF with text content', async () => {
    const doc = PDFDocument.create();
    const page = doc.addPage({ size: 'A4' });
    const font = doc.getStandardFont('Helvetica');

    page.drawText('Hello, World!', {
      x: 50,
      y: 700,
      font,
      fontSize: 24,
    });

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);

    // Should contain font reference
    expect(text).toContain('/Type /Font');
    expect(text).toContain('/BaseFont /Helvetica');

    // Should have content stream
    expect(text).toContain('stream');
    expect(text).toContain('endstream');
  });

  it('creates a multi-page PDF', async () => {
    const doc = PDFDocument.create();
    doc.addPage({ size: 'A4' });
    doc.addPage({ size: 'Letter' });
    doc.addPage({ size: 'A4', orientation: 'landscape' });

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('/Count 3');
  });

  it('tokenizer can parse the generated PDF header', async () => {
    const doc = PDFDocument.create();
    doc.addPage();
    const bytes = await doc.save();

    const tokenizer = new Tokenizer(bytes);

    // The tokenizer should be able to skip the header comment
    // and find real tokens in the body
    let foundObj = false;
    for (let i = 0; i < 50; i++) {
      const token = tokenizer.nextToken();
      if (token.type === TokenType.EOF) break;
      if (token.type === TokenType.Keyword && token.value === 'obj') {
        foundObj = true;
        break;
      }
    }
    expect(foundObj).toBe(true);
  });

  it('tokenizer parses dict in generated PDF', async () => {
    const doc = PDFDocument.create();
    doc.addPage();
    const bytes = await doc.save();

    const tokenizer = new Tokenizer(bytes);

    let foundDictStart = false;
    let foundName = false;
    for (let i = 0; i < 100; i++) {
      const token = tokenizer.nextToken();
      if (token.type === TokenType.EOF) break;
      if (token.type === TokenType.DictStart) foundDictStart = true;
      if (token.type === TokenType.Name && token.value === 'Type') foundName = true;
      if (foundDictStart && foundName) break;
    }
    expect(foundDictStart).toBe(true);
    expect(foundName).toBe(true);
  });

  it('created PDF has correct page count in page tree', async () => {
    const doc = PDFDocument.create();
    doc.addPage();
    doc.addPage();

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);

    // Find /Count 2 in the page tree
    expect(text).toContain('/Count 2');
  });

  it('page rotation is included in PDF output', async () => {
    const doc = PDFDocument.create();
    const page = doc.addPage();
    page.setRotation(90);

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('/Rotate 90');
  });

  it('PDF with metadata includes info dict', async () => {
    const doc = PDFDocument.create();
    doc.setTitle('Test Title');
    doc.setAuthor('Test Author');
    doc.setSubject('Test Subject');
    doc.setCreator('Test Creator');
    doc.setProducer('Test Producer');
    doc.addPage();

    const bytes = await doc.save();
    const text = new TextDecoder().decode(bytes);

    expect(text).toContain('/Info');
    expect(text).toContain('/Title');
    expect(text).toContain('/Author');
    expect(text).toContain('/Subject');
    expect(text).toContain('/Creator');
    expect(text).toContain('/Producer');
    expect(text).toContain('/CreationDate');
  });

  it('generated PDF bytes start with binary marker', async () => {
    const doc = PDFDocument.create();
    doc.addPage();
    const bytes = await doc.save();

    // After the header line, there should be a binary comment line
    // starting with % and containing high bytes
    const secondLine = bytes.indexOf(0x0A) + 1;
    expect(bytes[secondLine]).toBe(0x25); // %
    expect(bytes[secondLine + 1]).toBeGreaterThan(0x7F); // binary byte
  });
});
