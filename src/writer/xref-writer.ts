import { ByteBuffer } from '../utils/buffer.js';

export interface XrefEntry {
  objectNumber: number;
  offset: number;
  generation: number;
  free: boolean;
}

/**
 * Pad a number with leading zeros to the specified width.
 */
function padLeft(n: number, width: number): string {
  let s = n.toString();
  while (s.length < width) s = '0' + s;
  return s;
}

/**
 * Group consecutive object numbers into subsections.
 * Each subsection is [startObjectNumber, entries[]].
 */
function groupSubsections(entries: XrefEntry[]): Array<[number, XrefEntry[]]> {
  if (entries.length === 0) return [];

  // Sort by object number
  const sorted = [...entries].sort((a, b) => a.objectNumber - b.objectNumber);

  const groups: Array<[number, XrefEntry[]]> = [];
  let currentStart = sorted[0].objectNumber;
  let currentEntries: XrefEntry[] = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    const entry = sorted[i];
    const prevObjNum = sorted[i - 1].objectNumber;
    if (entry.objectNumber === prevObjNum + 1) {
      currentEntries.push(entry);
    } else {
      groups.push([currentStart, currentEntries]);
      currentStart = entry.objectNumber;
      currentEntries = [entry];
    }
  }
  groups.push([currentStart, currentEntries]);

  return groups;
}

/**
 * Write a cross-reference table to the buffer.
 *
 * The entries array should include the free head entry (object 0) if desired.
 * This function prepends the standard object-0 free entry automatically:
 *   "0000000000 65535 f \n"
 *
 * Each xref line is exactly 20 bytes: 10-digit offset + space + 5-digit generation + space + 'n'|'f' + space + \n
 */
export function writeXrefTable(
  entries: XrefEntry[],
  buf: ByteBuffer
): void {
  // Ensure object 0 free entry is present
  const hasObj0 = entries.some(e => e.objectNumber === 0);
  const allEntries: XrefEntry[] = hasObj0
    ? entries
    : [{ objectNumber: 0, offset: 0, generation: 65535, free: true }, ...entries];

  const groups = groupSubsections(allEntries);

  buf.writeString('xref\n');

  for (const [startObj, groupEntries] of groups) {
    buf.writeString(`${startObj} ${groupEntries.length}\n`);
    for (const entry of groupEntries) {
      const offsetStr = padLeft(entry.offset, 10);
      const genStr = padLeft(entry.generation, 5);
      const flag = entry.free ? 'f' : 'n';
      // Exactly 20 bytes: 10 + 1 + 5 + 1 + 1 + 1 + \n = 20 (with space + \r\n or space + \n)
      // PDF spec says each entry is exactly 20 bytes including EOL.
      // Traditional format: "OOOOOOOOOO GGGGG X \r\n" (20 bytes with \r\n)
      // We use the two-byte EOL variant: "OOOOOOOOOO GGGGG X \r\n"
      buf.writeString(`${offsetStr} ${genStr} ${flag} \n`);
    }
  }
}
