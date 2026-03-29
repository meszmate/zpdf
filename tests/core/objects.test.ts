import { describe, it, expect } from 'vitest';
import {
  pdfBool, pdfNum, pdfStr, pdfLiteralStr, pdfHexStr, pdfStringRaw,
  pdfName, pdfArray, pdfDict, pdfStream, pdfRef, pdfNull,
  dictGet, dictGetName, dictGetNumber, dictGetArray, dictGetString,
  dictGetDict, dictGetRef, dictGetBool,
  isRef, isDict, isArray, isName, isNumber, isString, isStream, isBool, isNull,
} from '../../src/core/objects.js';

describe('pdfBool', () => {
  it('creates a true boolean', () => {
    const obj = pdfBool(true);
    expect(obj.type).toBe('bool');
    expect(obj.value).toBe(true);
  });

  it('creates a false boolean', () => {
    const obj = pdfBool(false);
    expect(obj.type).toBe('bool');
    expect(obj.value).toBe(false);
  });
});

describe('pdfNum', () => {
  it('creates an integer', () => {
    const obj = pdfNum(42);
    expect(obj.type).toBe('number');
    expect(obj.value).toBe(42);
  });

  it('creates a float', () => {
    const obj = pdfNum(3.14);
    expect(obj.type).toBe('number');
    expect(obj.value).toBeCloseTo(3.14);
  });

  it('creates a negative number', () => {
    const obj = pdfNum(-100);
    expect(obj.value).toBe(-100);
  });

  it('creates zero', () => {
    const obj = pdfNum(0);
    expect(obj.value).toBe(0);
  });
});

describe('pdfStr', () => {
  it('creates an ASCII literal string', () => {
    const obj = pdfStr('Hello');
    expect(obj.type).toBe('string');
    expect(obj.encoding).toBe('literal');
    expect(obj.value).toEqual(new Uint8Array([72, 101, 108, 108, 111]));
  });

  it('creates a UTF-16BE hex string for non-ASCII', () => {
    const obj = pdfStr('\u00e9'); // e with acute
    expect(obj.type).toBe('string');
    expect(obj.encoding).toBe('hex');
    // BOM + UTF-16BE encoding of U+00E9
    expect(obj.value[0]).toBe(0xFE);
    expect(obj.value[1]).toBe(0xFF);
    expect(obj.value[2]).toBe(0x00);
    expect(obj.value[3]).toBe(0xE9);
  });

  it('treats tilde (0x7E) as ASCII-safe boundary', () => {
    const obj = pdfStr('~');
    expect(obj.encoding).toBe('literal');
  });

  it('treats DEL (0x7F) as non-ASCII', () => {
    const obj = pdfStr('\x7F');
    expect(obj.encoding).toBe('hex');
  });
});

describe('pdfLiteralStr', () => {
  it('forces literal encoding regardless of content', () => {
    const obj = pdfLiteralStr('test');
    expect(obj.encoding).toBe('literal');
    expect(obj.value.length).toBe(4);
    expect(obj.value[0]).toBe(116); // 't'
  });
});

describe('pdfHexStr', () => {
  it('creates from hex string', () => {
    const obj = pdfHexStr('48656C6C6F');
    expect(obj.encoding).toBe('hex');
    expect(obj.value).toEqual(new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]));
  });

  it('creates from Uint8Array', () => {
    const data = new Uint8Array([1, 2, 3]);
    const obj = pdfHexStr(data);
    expect(obj.encoding).toBe('hex');
    expect(obj.value).toBe(data);
  });

  it('ignores whitespace in hex string', () => {
    const obj = pdfHexStr('48 65 6C');
    expect(obj.value).toEqual(new Uint8Array([0x48, 0x65, 0x6C]));
  });
});

describe('pdfStringRaw', () => {
  it('creates a raw string with literal encoding', () => {
    const data = new Uint8Array([65, 66]);
    const obj = pdfStringRaw(data);
    expect(obj.encoding).toBe('literal');
    expect(obj.value).toBe(data);
  });

  it('creates a raw string with hex encoding', () => {
    const data = new Uint8Array([65, 66]);
    const obj = pdfStringRaw(data, 'hex');
    expect(obj.encoding).toBe('hex');
  });
});

describe('pdfName', () => {
  it('creates a name', () => {
    const obj = pdfName('Type');
    expect(obj.type).toBe('name');
    expect(obj.value).toBe('Type');
  });
});

describe('pdfArray', () => {
  it('creates an empty array', () => {
    const obj = pdfArray();
    expect(obj.type).toBe('array');
    expect(obj.items).toEqual([]);
  });

  it('creates an array with items', () => {
    const obj = pdfArray(pdfNum(1), pdfNum(2), pdfName('Test'));
    expect(obj.items.length).toBe(3);
    expect(obj.items[0].type).toBe('number');
    expect(obj.items[2].type).toBe('name');
  });
});

describe('pdfDict', () => {
  it('creates an empty dict', () => {
    const obj = pdfDict();
    expect(obj.type).toBe('dict');
    expect(obj.entries.size).toBe(0);
  });

  it('creates a dict from a plain object', () => {
    const obj = pdfDict({ Type: pdfName('Page'), Count: pdfNum(5) });
    expect(obj.entries.size).toBe(2);
    expect(obj.entries.get('Type')).toEqual(pdfName('Page'));
    expect(obj.entries.get('Count')).toEqual(pdfNum(5));
  });

  it('creates a dict from a Map', () => {
    const map = new Map<string, any>();
    map.set('Key', pdfNum(10));
    const obj = pdfDict(map);
    expect(obj.entries.get('Key')).toEqual(pdfNum(10));
  });
});

describe('pdfStream', () => {
  it('creates a stream with data and dict', () => {
    const data = new Uint8Array([1, 2, 3]);
    const obj = pdfStream({ Length: pdfNum(3) }, data);
    expect(obj.type).toBe('stream');
    expect(obj.data).toBe(data);
    expect(obj.dict.get('Length')).toEqual(pdfNum(3));
  });
});

describe('pdfRef', () => {
  it('creates a reference with default generation 0', () => {
    const obj = pdfRef(10);
    expect(obj.type).toBe('ref');
    expect(obj.objectNumber).toBe(10);
    expect(obj.generation).toBe(0);
  });

  it('creates a reference with explicit generation', () => {
    const obj = pdfRef(10, 2);
    expect(obj.generation).toBe(2);
  });
});

describe('pdfNull', () => {
  it('creates a null object', () => {
    const obj = pdfNull();
    expect(obj.type).toBe('null');
  });
});

describe('dictGet* helpers', () => {
  const dict = pdfDict({
    Name: pdfName('Page'),
    Count: pdfNum(42),
    Items: pdfArray(pdfNum(1)),
    Title: pdfLiteralStr('Hello'),
    Nested: pdfDict({ Inner: pdfNum(7) }),
    Ref: pdfRef(5, 0),
    Flag: pdfBool(true),
  });

  it('dictGet returns the raw object', () => {
    expect(dictGet(dict, 'Name')).toEqual(pdfName('Page'));
    expect(dictGet(dict, 'Missing')).toBeUndefined();
  });

  it('dictGetName returns the name string', () => {
    expect(dictGetName(dict, 'Name')).toBe('Page');
    expect(dictGetName(dict, 'Count')).toBeUndefined();
  });

  it('dictGetNumber returns the number', () => {
    expect(dictGetNumber(dict, 'Count')).toBe(42);
    expect(dictGetNumber(dict, 'Name')).toBeUndefined();
  });

  it('dictGetArray returns the items array', () => {
    const items = dictGetArray(dict, 'Items');
    expect(items).toBeDefined();
    expect(items!.length).toBe(1);
  });

  it('dictGetString returns decoded string', () => {
    expect(dictGetString(dict, 'Title')).toBe('Hello');
    expect(dictGetString(dict, 'Count')).toBeUndefined();
  });

  it('dictGetDict returns nested dict', () => {
    const nested = dictGetDict(dict, 'Nested');
    expect(nested).toBeDefined();
    expect(nested!.entries.get('Inner')).toEqual(pdfNum(7));
  });

  it('dictGetRef returns a ref', () => {
    const ref = dictGetRef(dict, 'Ref');
    expect(ref).toBeDefined();
    expect(ref!.objectNumber).toBe(5);
  });

  it('dictGetBool returns boolean', () => {
    expect(dictGetBool(dict, 'Flag')).toBe(true);
    expect(dictGetBool(dict, 'Name')).toBeUndefined();
  });

  it('works with a stream object', () => {
    const stream = pdfStream({ Type: pdfName('XObject') }, new Uint8Array(0));
    expect(dictGetName(stream, 'Type')).toBe('XObject');
  });
});

describe('type guards', () => {
  it('isRef', () => {
    expect(isRef(pdfRef(1))).toBe(true);
    expect(isRef(pdfNum(1))).toBe(false);
  });

  it('isDict', () => {
    expect(isDict(pdfDict())).toBe(true);
    expect(isDict(pdfArray())).toBe(false);
  });

  it('isArray', () => {
    expect(isArray(pdfArray())).toBe(true);
    expect(isArray(pdfDict())).toBe(false);
  });

  it('isName', () => {
    expect(isName(pdfName('X'))).toBe(true);
    expect(isName(pdfNum(1))).toBe(false);
  });

  it('isNumber', () => {
    expect(isNumber(pdfNum(5))).toBe(true);
    expect(isNumber(pdfBool(true))).toBe(false);
  });

  it('isString', () => {
    expect(isString(pdfStr('test'))).toBe(true);
    expect(isString(pdfNum(1))).toBe(false);
  });

  it('isStream', () => {
    expect(isStream(pdfStream({}, new Uint8Array(0)))).toBe(true);
    expect(isStream(pdfDict())).toBe(false);
  });

  it('isBool', () => {
    expect(isBool(pdfBool(false))).toBe(true);
    expect(isBool(pdfNull())).toBe(false);
  });

  it('isNull', () => {
    expect(isNull(pdfNull())).toBe(true);
    expect(isNull(pdfNum(0))).toBe(false);
  });
});
