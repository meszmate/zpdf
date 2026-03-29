import type { PdfRef } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfStream, pdfName } from '../core/objects.js';
import type { DocumentInfo } from './info-dict.js';

function escapeXml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function toISODate(d: Date): string {
  return d.toISOString();
}

/**
 * Generate an XMP metadata XML packet.
 * Supports Dublin Core, XMP basic, PDF properties, and optional PDF/A identification.
 */
export function createXMPMetadata(info: DocumentInfo, pdfALevel?: 'a' | 'b' | 'u'): string {
  const parts: string[] = [];

  parts.push('<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>');
  parts.push('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
  parts.push('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
  parts.push('<rdf:Description rdf:about=""');
  parts.push('  xmlns:dc="http://purl.org/dc/elements/1.1/"');
  parts.push('  xmlns:xmp="http://ns.adobe.com/xap/1.0/"');
  parts.push('  xmlns:pdf="http://ns.adobe.com/pdf/1.3/"');
  if (pdfALevel) {
    parts.push('  xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"');
  }
  parts.push('>');

  // Dublin Core
  if (info.title) {
    parts.push('<dc:title>');
    parts.push('  <rdf:Alt>');
    parts.push(`    <rdf:li xml:lang="x-default">${escapeXml(info.title)}</rdf:li>`);
    parts.push('  </rdf:Alt>');
    parts.push('</dc:title>');
  }

  if (info.author) {
    parts.push('<dc:creator>');
    parts.push('  <rdf:Seq>');
    parts.push(`    <rdf:li>${escapeXml(info.author)}</rdf:li>`);
    parts.push('  </rdf:Seq>');
    parts.push('</dc:creator>');
  }

  if (info.subject) {
    parts.push('<dc:description>');
    parts.push('  <rdf:Alt>');
    parts.push(`    <rdf:li xml:lang="x-default">${escapeXml(info.subject)}</rdf:li>`);
    parts.push('  </rdf:Alt>');
    parts.push('</dc:description>');
  }

  if (info.keywords && info.keywords.length > 0) {
    parts.push('<dc:subject>');
    parts.push('  <rdf:Bag>');
    for (const kw of info.keywords) {
      parts.push(`    <rdf:li>${escapeXml(kw)}</rdf:li>`);
    }
    parts.push('  </rdf:Bag>');
    parts.push('</dc:subject>');
  }

  // XMP basic
  if (info.creationDate) {
    parts.push(`<xmp:CreateDate>${toISODate(info.creationDate)}</xmp:CreateDate>`);
  }
  if (info.modDate) {
    parts.push(`<xmp:ModifyDate>${toISODate(info.modDate)}</xmp:ModifyDate>`);
  }
  if (info.creator) {
    parts.push(`<xmp:CreatorTool>${escapeXml(info.creator)}</xmp:CreatorTool>`);
  }

  // PDF properties
  if (info.producer) {
    parts.push(`<pdf:Producer>${escapeXml(info.producer)}</pdf:Producer>`);
  }
  if (info.keywords && info.keywords.length > 0) {
    parts.push(`<pdf:Keywords>${escapeXml(info.keywords.join(', '))}</pdf:Keywords>`);
  }

  // PDF/A identification
  if (pdfALevel) {
    // Parse level like 'a', 'b', 'u' - the part number comes from the caller context
    parts.push(`<pdfaid:part>1</pdfaid:part>`);
    parts.push(`<pdfaid:conformance>${pdfALevel.toUpperCase()}</pdfaid:conformance>`);
  }

  parts.push('</rdf:Description>');
  parts.push('</rdf:RDF>');
  parts.push('</x:xmpmeta>');

  // Add padding for in-place editing
  for (let i = 0; i < 20; i++) {
    parts.push('                                                                                ');
  }

  parts.push('<?xpacket end="w"?>');

  return parts.join('\n');
}

/**
 * Embed XMP metadata as a stream object in the object store.
 * Returns a ref to the metadata stream.
 */
export function embedXMPMetadata(store: ObjectStore, xmp: string): PdfRef {
  const encoder = new TextEncoder();
  const data = encoder.encode(xmp);

  const ref = store.allocRef();
  const stream = pdfStream(
    {
      Type: pdfName('Metadata'),
      Subtype: pdfName('XML'),
    },
    data,
  );
  store.set(ref, stream);
  return ref;
}
