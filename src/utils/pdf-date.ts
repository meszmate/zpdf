import { formatPdfDate, parsePdfDate } from './string-utils.js';

export { formatPdfDate, parsePdfDate };

export function currentPdfDate(): string {
  return formatPdfDate(new Date());
}
