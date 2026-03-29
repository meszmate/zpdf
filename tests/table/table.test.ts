import { describe, it, expect } from 'vitest';
import { Table } from '../../src/table/table.js';
import { TableCell } from '../../src/table/cell.js';

describe('Table', () => {
  it('creates an empty table', () => {
    const table = new Table();
    expect(table.getRows()).toEqual([]);
    expect(table.getHeaders()).toEqual([]);
    expect(table.getColumnWidths()).toEqual([]);
  });

  it('creates a table with style', () => {
    const table = new Table({ borderWidth: 1, borderColor: { type: 'grayscale', gray: 0 } });
    expect(table.getStyle().borderWidth).toBe(1);
  });

  it('adds rows with string cells', () => {
    const table = new Table();
    table.addRow(['A', 'B', 'C']);
    expect(table.getRows().length).toBe(1);
    expect(table.getRows()[0].length).toBe(3);
    expect(table.getRows()[0][0]).toBeInstanceOf(TableCell);
    expect(table.getRows()[0][0].content).toBe('A');
  });

  it('adds rows with TableCell objects', () => {
    const table = new Table();
    const cell = new TableCell('Custom', { colspan: 2 });
    table.addRow([cell, 'Normal']);
    expect(table.getRows()[0][0].colspan).toBe(2);
    expect(table.getRows()[0][1].content).toBe('Normal');
  });

  it('adds header rows', () => {
    const table = new Table();
    table.addHeaderRow(['H1', 'H2', 'H3']);
    expect(table.getHeaders().length).toBe(1);
    expect(table.getHeaders()[0][0].content).toBe('H1');
  });

  it('sets column widths', () => {
    const table = new Table();
    table.setColumnWidths([100, 200, 'auto']);
    expect(table.getColumnWidths()).toEqual([100, 200, 'auto']);
  });

  it('supports method chaining', () => {
    const table = new Table();
    const result = table
      .setColumnWidths([100, 200])
      .addHeaderRow(['A', 'B'])
      .addRow(['1', '2']);
    expect(result).toBe(table);
  });
});

describe('TableCell', () => {
  it('creates with default options', () => {
    const cell = new TableCell('text');
    expect(cell.content).toBe('text');
    expect(cell.colspan).toBe(1);
    expect(cell.rowspan).toBe(1);
    expect(cell.style).toEqual({});
  });

  it('creates with custom options', () => {
    const cell = new TableCell('text', {
      colspan: 3,
      rowspan: 2,
      style: { padding: 10 },
    });
    expect(cell.colspan).toBe(3);
    expect(cell.rowspan).toBe(2);
    expect(cell.style.padding).toBe(10);
  });
});
