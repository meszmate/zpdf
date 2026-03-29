import type {
  PdfBool, PdfNumber, PdfString, PdfName, PdfArray, PdfDict,
  PdfStream, PdfNull, PdfRef, PdfObject,
} from './types.js';

export function pdfBool(value: boolean): PdfBool {
  return { type: 'bool', value };
}

export function pdfNum(value: number): PdfNumber {
  return { type: 'number', value };
}

export function pdfStr(value: string): PdfString {
  // Check if string is ASCII-safe
  let ascii = true;
  for (let i = 0; i < value.length; i++) {
    if (value.charCodeAt(i) > 0x7e) {
      ascii = false;
      break;
    }
  }
  if (ascii) {
    const bytes = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i++) {
      bytes[i] = value.charCodeAt(i) & 0xff;
    }
    return { type: 'string', value: bytes, encoding: 'literal' };
  }
  // Non-ASCII: encode as UTF-16BE with BOM
  const codeUnits: number[] = [];
  for (let i = 0; i < value.length; i++) {
    codeUnits.push(value.charCodeAt(i));
  }
  const bytes = new Uint8Array(2 + codeUnits.length * 2);
  bytes[0] = 0xfe;
  bytes[1] = 0xff;
  for (let i = 0; i < codeUnits.length; i++) {
    bytes[2 + i * 2] = (codeUnits[i] >>> 8) & 0xff;
    bytes[2 + i * 2 + 1] = codeUnits[i] & 0xff;
  }
  return { type: 'string', value: bytes, encoding: 'hex' };
}

export function pdfLiteralStr(value: string): PdfString {
  const bytes = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) {
    bytes[i] = value.charCodeAt(i) & 0xff;
  }
  return { type: 'string', value: bytes, encoding: 'literal' };
}

export function pdfHexStr(value: string | Uint8Array): PdfString {
  if (value instanceof Uint8Array) {
    return { type: 'string', value, encoding: 'hex' };
  }
  const clean = value.replace(/\s/g, '');
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return { type: 'string', value: bytes, encoding: 'hex' };
}

export function pdfStringRaw(value: Uint8Array, encoding: 'literal' | 'hex' = 'literal'): PdfString {
  return { type: 'string', value, encoding };
}

export function pdfName(value: string): PdfName {
  return { type: 'name', value };
}

export function pdfArray(...items: PdfObject[]): PdfArray {
  return { type: 'array', items };
}

export function pdfDict(entries?: Record<string, PdfObject> | Map<string, PdfObject>): PdfDict {
  let map: Map<string, PdfObject>;
  if (entries instanceof Map) {
    map = new Map(entries);
  } else if (entries) {
    map = new Map(Object.entries(entries));
  } else {
    map = new Map();
  }
  return { type: 'dict', entries: map };
}

export function pdfStream(dict: Record<string, PdfObject> | Map<string, PdfObject>, data: Uint8Array): PdfStream {
  let map: Map<string, PdfObject>;
  if (dict instanceof Map) {
    map = new Map(dict);
  } else {
    map = new Map(Object.entries(dict));
  }
  return { type: 'stream', dict: map, data };
}

export function pdfRef(objectNumber: number, generation: number = 0): PdfRef {
  return { type: 'ref', objectNumber, generation };
}

export function pdfNull(): PdfNull {
  return { type: 'null' };
}

// Helper: get entries map from dict or stream
function getEntries(dict: PdfDict | PdfStream): Map<string, PdfObject> {
  return dict.type === 'dict' ? dict.entries : dict.dict;
}

export function dictGet(dict: PdfDict | PdfStream, key: string): PdfObject | undefined {
  return getEntries(dict).get(key);
}

export function dictGetName(dict: PdfDict | PdfStream, key: string): string | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'name') return obj.value;
  return undefined;
}

export function dictGetNumber(dict: PdfDict | PdfStream, key: string): number | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'number') return obj.value;
  return undefined;
}

export function dictGetArray(dict: PdfDict | PdfStream, key: string): PdfObject[] | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'array') return obj.items;
  return undefined;
}

export function dictGetString(dict: PdfDict | PdfStream, key: string): string | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'string') {
    let s = '';
    for (let i = 0; i < obj.value.length; i++) {
      s += String.fromCharCode(obj.value[i]);
    }
    return s;
  }
  return undefined;
}

export function dictGetDict(dict: PdfDict | PdfStream, key: string): PdfDict | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'dict') return obj;
  return undefined;
}

export function dictGetRef(dict: PdfDict | PdfStream, key: string): PdfRef | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'ref') return obj;
  return undefined;
}

export function dictGetBool(dict: PdfDict | PdfStream, key: string): boolean | undefined {
  const obj = getEntries(dict).get(key);
  if (obj && obj.type === 'bool') return obj.value;
  return undefined;
}

// Type guards

export function isRef(obj: PdfObject): obj is PdfRef {
  return obj.type === 'ref';
}

export function isDict(obj: PdfObject): obj is PdfDict {
  return obj.type === 'dict';
}

export function isArray(obj: PdfObject): obj is PdfArray {
  return obj.type === 'array';
}

export function isName(obj: PdfObject): obj is PdfName {
  return obj.type === 'name';
}

export function isNumber(obj: PdfObject): obj is PdfNumber {
  return obj.type === 'number';
}

export function isString(obj: PdfObject): obj is PdfString {
  return obj.type === 'string';
}

export function isStream(obj: PdfObject): obj is PdfStream {
  return obj.type === 'stream';
}

export function isBool(obj: PdfObject): obj is PdfBool {
  return obj.type === 'bool';
}

export function isNull(obj: PdfObject): obj is PdfNull {
  return obj.type === 'null';
}
