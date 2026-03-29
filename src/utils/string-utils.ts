/**
 * PDF string utilities.
 */

export function escapePdfString(s: string): string {
  let result = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    switch (ch) {
      case '\\':
        result += '\\\\';
        break;
      case '(':
        result += '\\(';
        break;
      case ')':
        result += '\\)';
        break;
      case '\r':
        result += '\\r';
        break;
      case '\n':
        result += '\\n';
        break;
      case '\t':
        result += '\\t';
        break;
      case '\b':
        result += '\\b';
        break;
      case '\f':
        result += '\\f';
        break;
      default:
        result += ch;
        break;
    }
  }
  return result;
}

function pad2(n: number): string {
  return n.toString().padStart(2, '0');
}

export function formatPdfDate(date: Date): string {
  const offset = date.getTimezoneOffset();
  const sign = offset <= 0 ? '+' : '-';
  const absOffset = Math.abs(offset);
  const offHours = Math.floor(absOffset / 60);
  const offMinutes = absOffset % 60;

  return (
    'D:' +
    date.getFullYear().toString() +
    pad2(date.getMonth() + 1) +
    pad2(date.getDate()) +
    pad2(date.getHours()) +
    pad2(date.getMinutes()) +
    pad2(date.getSeconds()) +
    sign +
    pad2(offHours) +
    "'" +
    pad2(offMinutes) +
    "'"
  );
}

export function parsePdfDate(s: string): Date | null {
  // Format: D:YYYYMMDDHHmmSSOHH'mm' (various parts optional)
  let str = s;
  if (str.startsWith('D:')) {
    str = str.substring(2);
  }
  if (str.length < 4) return null;

  const year = parseInt(str.substring(0, 4), 10);
  const month = str.length >= 6 ? parseInt(str.substring(4, 6), 10) : 1;
  const day = str.length >= 8 ? parseInt(str.substring(6, 8), 10) : 1;
  const hour = str.length >= 10 ? parseInt(str.substring(8, 10), 10) : 0;
  const minute = str.length >= 12 ? parseInt(str.substring(10, 12), 10) : 0;
  const second = str.length >= 14 ? parseInt(str.substring(12, 14), 10) : 0;

  if (isNaN(year) || isNaN(month) || isNaN(day) || isNaN(hour) || isNaN(minute) || isNaN(second)) {
    return null;
  }

  // Parse timezone
  let tzOffsetMinutes = 0;
  if (str.length > 14) {
    const tzPart = str.substring(14);
    const tzSign = tzPart[0];
    if (tzSign === 'Z') {
      tzOffsetMinutes = 0;
    } else if (tzSign === '+' || tzSign === '-') {
      const tzStr = tzPart.substring(1).replace(/'/g, '');
      const tzHours = parseInt(tzStr.substring(0, 2), 10) || 0;
      const tzMins = parseInt(tzStr.substring(2, 4), 10) || 0;
      tzOffsetMinutes = (tzHours * 60 + tzMins) * (tzSign === '+' ? 1 : -1);
    }
  }

  // Create date in UTC then adjust for timezone offset
  const utcMs = Date.UTC(year, month - 1, day, hour, minute, second) - tzOffsetMinutes * 60000;
  return new Date(utcMs);
}

export function numberToString(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  // Use fixed precision and strip trailing zeros
  let s = n.toFixed(6);
  // Remove trailing zeros after decimal point
  if (s.includes('.')) {
    s = s.replace(/0+$/, '');
    s = s.replace(/\.$/, '');
  }
  // Handle negative zero
  if (s === '-0') return '0';
  return s;
}

export function hexEncode(bytes: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0').toUpperCase();
  }
  return hex;
}

export function hexDecode(hex: string): Uint8Array {
  const cleaned = hex.replace(/\s/g, '');
  const len = cleaned.length;
  // If odd length, pad with trailing 0 (PDF spec)
  const padded = len % 2 === 1 ? cleaned + '0' : cleaned;
  const result = new Uint8Array(padded.length / 2);
  for (let i = 0; i < result.length; i++) {
    result[i] = parseInt(padded.substring(i * 2, i * 2 + 2), 16);
  }
  return result;
}
