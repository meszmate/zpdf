import { describe, it, expect } from 'vitest';
import { writePdf } from '../../src/writer/pdf-writer.js';
import { ObjectStore } from '../../src/core/object-store.js';
import { pdfDict, pdfName, pdfNum, pdfArray, pdfRef, pdfStream } from '../../src/core/objects.js';

describe('writePdf', () => {
  it('generates a valid PDF header', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({
      Type: pdfName('Catalog'),
      Pages: pdfRef(99),
    }));

    const bytes = await writePdf(store, catalogRef, { version: '1.7' });
    const text = new TextDecoder().decode(bytes.subarray(0, 20));
    expect(text).toContain('%PDF-1.7');
  });

  it('includes %%EOF marker', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('%%EOF');
  });

  it('includes xref table', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('xref');
    expect(text).toContain('startxref');
  });

  it('includes trailer with /Root and /Size', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('trailer');
    expect(text).toContain('/Root');
    expect(text).toContain('/Size');
  });

  it('includes /Info when provided', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    const infoRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));
    store.set(infoRef, pdfDict({ Title: { type: 'string', value: new TextEncoder().encode('Test'), encoding: 'literal' as const } }));

    const bytes = await writePdf(store, catalogRef, { info: infoRef });
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('/Info');
  });

  it('writes all objects in the store', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    const pagesRef = store.allocRef();
    const pageRef = store.allocRef();

    store.set(catalogRef, pdfDict({
      Type: pdfName('Catalog'),
      Pages: pagesRef,
    }));
    store.set(pagesRef, pdfDict({
      Type: pdfName('Pages'),
      Kids: pdfArray(pageRef),
      Count: pdfNum(1),
    }));
    store.set(pageRef, pdfDict({
      Type: pdfName('Page'),
    }));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes);

    // Should have "1 0 obj", "2 0 obj", "3 0 obj"
    expect(text).toContain('1 0 obj');
    expect(text).toContain('2 0 obj');
    expect(text).toContain('3 0 obj');
    expect(text).toContain('endobj');
  });

  it('uses default version 1.7', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes.subarray(0, 20));
    expect(text).toContain('%PDF-1.7');
  });

  it('writes stream objects correctly', async () => {
    const store = new ObjectStore();
    const catalogRef = store.allocRef();
    store.set(catalogRef, pdfDict({ Type: pdfName('Catalog') }));

    const streamRef = store.allocRef();
    const data = new TextEncoder().encode('Hello stream');
    store.set(streamRef, pdfStream({}, data));

    const bytes = await writePdf(store, catalogRef);
    const text = new TextDecoder().decode(bytes);
    expect(text).toContain('stream');
    expect(text).toContain('endstream');
    expect(text).toContain('/Length 12'); // "Hello stream" = 12 bytes
  });
});
