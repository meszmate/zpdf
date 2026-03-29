export const PageSizes = {
  A0: [2384, 3370] as const,
  A1: [1684, 2384] as const,
  A2: [1191, 1684] as const,
  A3: [842, 1191] as const,
  A4: [595, 842] as const,
  A5: [420, 595] as const,
  A6: [298, 420] as const,
  A7: [210, 298] as const,
  A8: [148, 210] as const,
  B0: [2835, 4008] as const,
  B1: [2004, 2835] as const,
  B2: [1417, 2004] as const,
  B3: [1001, 1417] as const,
  B4: [709, 1001] as const,
  B5: [499, 709] as const,
  Letter: [612, 792] as const,
  Legal: [612, 1008] as const,
  Tabloid: [792, 1224] as const,
  Ledger: [1224, 792] as const,
  Executive: [522, 756] as const,
  Folio: [612, 936] as const,
  Quarto: [610, 780] as const,
  '10x14': [720, 1008] as const,
  '11x17': [792, 1224] as const,
} as const;

export type PageSizeName = keyof typeof PageSizes;
export type Orientation = 'portrait' | 'landscape';
