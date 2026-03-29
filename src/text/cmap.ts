/**
 * CMap handling for Unicode text in PDF.
 * Parses and generates ToUnicode CMaps.
 */

/**
 * Parse a ToUnicode CMap string, extracting CID -> Unicode mappings.
 */
export function parseCMap(cmapData: string): Map<number, number> {
  const mapping = new Map<number, number>();

  // Parse beginbfchar/endbfchar sections
  const bfcharRegex = /beginbfchar\s*([\s\S]*?)endbfchar/g;
  let match: RegExpExecArray | null;

  while ((match = bfcharRegex.exec(cmapData)) !== null) {
    const block = match[1].trim();
    const lines = block.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      // Each line: <srcCode> <dstCode>
      const parts = trimmed.match(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/);
      if (parts) {
        const srcCode = parseInt(parts[1], 16);
        const dstUnicode = parseInt(parts[2], 16);
        mapping.set(srcCode, dstUnicode);
      }
    }
  }

  // Parse beginbfrange/endbfrange sections
  const bfrangeRegex = /beginbfrange\s*([\s\S]*?)endbfrange/g;

  while ((match = bfrangeRegex.exec(cmapData)) !== null) {
    const block = match[1].trim();
    const lines = block.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      // Range with single destination: <start> <end> <dstStart>
      const rangeMatch = trimmed.match(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/);
      if (rangeMatch) {
        const start = parseInt(rangeMatch[1], 16);
        const end = parseInt(rangeMatch[2], 16);
        const dstStart = parseInt(rangeMatch[3], 16);
        for (let i = start; i <= end; i++) {
          mapping.set(i, dstStart + (i - start));
        }
        continue;
      }

      // Range with array of destinations: <start> <end> [<dst1> <dst2> ...]
      const arrayMatch = trimmed.match(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*\[([^\]]*)\]/);
      if (arrayMatch) {
        const start = parseInt(arrayMatch[1], 16);
        const end = parseInt(arrayMatch[2], 16);
        const dstCodes = arrayMatch[3].match(/<([0-9a-fA-F]+)>/g);
        if (dstCodes) {
          for (let i = 0; i < dstCodes.length && (start + i) <= end; i++) {
            const hexStr = dstCodes[i].replace(/[<>]/g, '');
            mapping.set(start + i, parseInt(hexStr, 16));
          }
        }
      }
    }
  }

  return mapping;
}

/**
 * Generate a ToUnicode CMap string from a CID -> Unicode mapping.
 * Groups consecutive ranges for efficiency.
 */
export function generateToUnicodeCMap(mapping: Map<number, number>): string {
  if (mapping.size === 0) {
    return '';
  }

  // Sort entries by CID
  const entries = Array.from(mapping.entries()).sort((a, b) => a[0] - b[0]);

  // Group into consecutive ranges where unicode = cid_unicode_start + (cid - cid_start)
  interface Range {
    cidStart: number;
    cidEnd: number;
    unicodeStart: number;
  }

  const ranges: Range[] = [];
  const singles: Array<[number, number]> = [];

  let i = 0;
  while (i < entries.length) {
    const [cidStart, unicodeStart] = entries[i];
    let cidEnd = cidStart;

    // Try to extend this range
    while (
      i + 1 < entries.length &&
      entries[i + 1][0] === cidEnd + 1 &&
      entries[i + 1][1] === unicodeStart + (entries[i + 1][0] - cidStart)
    ) {
      i++;
      cidEnd = entries[i][0];
    }

    if (cidEnd > cidStart) {
      ranges.push({ cidStart, cidEnd, unicodeStart });
    } else {
      singles.push([cidStart, unicodeStart]);
    }
    i++;
  }

  // Build CMap string
  const lines: string[] = [];
  lines.push('/CIDInit /ProcSet findresource begin');
  lines.push('12 dict begin');
  lines.push('begincmap');
  lines.push('/CIDSystemInfo');
  lines.push('<< /Registry (Adobe)');
  lines.push('/Ordering (UCS)');
  lines.push('/Supplement 0');
  lines.push('>> def');
  lines.push('/CMapName /Adobe-Identity-UCS def');
  lines.push('/CMapType 2 def');
  lines.push('1 begincodespacerange');
  lines.push('<0000> <FFFF>');
  lines.push('endcodespacerange');

  // Write bfchar entries in blocks of up to 100
  if (singles.length > 0) {
    for (let s = 0; s < singles.length; s += 100) {
      const block = singles.slice(s, s + 100);
      lines.push(`${block.length} beginbfchar`);
      for (const [cid, unicode] of block) {
        lines.push(
          `<${cid.toString(16).toUpperCase().padStart(4, '0')}> ` +
          `<${unicode.toString(16).toUpperCase().padStart(4, '0')}>`,
        );
      }
      lines.push('endbfchar');
    }
  }

  // Write bfrange entries in blocks of up to 100
  if (ranges.length > 0) {
    for (let r = 0; r < ranges.length; r += 100) {
      const block = ranges.slice(r, r + 100);
      lines.push(`${block.length} beginbfrange`);
      for (const range of block) {
        lines.push(
          `<${range.cidStart.toString(16).toUpperCase().padStart(4, '0')}> ` +
          `<${range.cidEnd.toString(16).toUpperCase().padStart(4, '0')}> ` +
          `<${range.unicodeStart.toString(16).toUpperCase().padStart(4, '0')}>`,
        );
      }
      lines.push('endbfrange');
    }
  }

  lines.push('endcmap');
  lines.push('CMapName currentdict /CMap defineresource pop');
  lines.push('end');
  lines.push('end');

  return lines.join('\n');
}
