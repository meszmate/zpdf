import { describe, it, expect } from 'vitest';
import { ObjectStore } from '../../src/core/object-store.js';
import { pdfNum, pdfName, pdfDict, pdfRef } from '../../src/core/objects.js';

describe('ObjectStore', () => {
  it('starts empty', () => {
    const store = new ObjectStore();
    expect(store.size).toBe(0);
    expect(store.nextObjectNumber).toBe(1);
  });

  it('allocRef increments object numbers', () => {
    const store = new ObjectStore();
    const ref1 = store.allocRef();
    const ref2 = store.allocRef();
    expect(ref1.objectNumber).toBe(1);
    expect(ref1.generation).toBe(0);
    expect(ref2.objectNumber).toBe(2);
    expect(store.nextObjectNumber).toBe(3);
  });

  it('allocRef respects generation parameter', () => {
    const store = new ObjectStore();
    const ref = store.allocRef(5);
    expect(ref.generation).toBe(5);
  });

  it('set and get an object', () => {
    const store = new ObjectStore();
    const ref = store.allocRef();
    const obj = pdfNum(42);
    store.set(ref, obj);
    expect(store.get(ref)).toBe(obj);
    expect(store.size).toBe(1);
  });

  it('has returns true for stored objects', () => {
    const store = new ObjectStore();
    const ref = store.allocRef();
    store.set(ref, pdfName('Test'));
    expect(store.has(ref)).toBe(true);
    expect(store.has(pdfRef(999))).toBe(false);
  });

  it('delete removes an object', () => {
    const store = new ObjectStore();
    const ref = store.allocRef();
    store.set(ref, pdfNum(10));
    expect(store.size).toBe(1);
    store.delete(ref);
    expect(store.size).toBe(0);
    expect(store.get(ref)).toBeUndefined();
    expect(store.has(ref)).toBe(false);
  });

  it('set with external ref updates nextObjectNumber', () => {
    const store = new ObjectStore();
    const externalRef = pdfRef(50, 0);
    store.set(externalRef, pdfName('External'));
    expect(store.nextObjectNumber).toBe(51);
  });

  it('entries iterator yields all entries', () => {
    const store = new ObjectStore();
    const ref1 = store.allocRef();
    const ref2 = store.allocRef();
    store.set(ref1, pdfNum(1));
    store.set(ref2, pdfNum(2));

    const entries = [...store.entries()];
    expect(entries.length).toBe(2);

    const objNums = entries.map(([ref]) => ref.objectNumber).sort();
    expect(objNums).toEqual([1, 2]);
  });

  it('distinguishes refs with different generations', () => {
    const store = new ObjectStore();
    const ref1 = pdfRef(1, 0);
    const ref2 = pdfRef(1, 1);
    store.set(ref1, pdfNum(100));
    store.set(ref2, pdfNum(200));
    expect(store.size).toBe(2);
    expect(store.get(ref1)).toEqual(pdfNum(100));
    expect(store.get(ref2)).toEqual(pdfNum(200));
  });

  it('overwriting the same ref replaces the object', () => {
    const store = new ObjectStore();
    const ref = store.allocRef();
    store.set(ref, pdfNum(1));
    store.set(ref, pdfNum(2));
    expect(store.size).toBe(1);
    expect(store.get(ref)).toEqual(pdfNum(2));
  });
});
