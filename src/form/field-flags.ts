export const FieldFlags = {
  ReadOnly: 1 << 0,
  Required: 1 << 1,
  NoExport: 1 << 2,
  // Text field specific
  Multiline: 1 << 12,
  Password: 1 << 13,
  FileSelect: 1 << 20,
  DoNotSpellCheck: 1 << 22,
  DoNotScroll: 1 << 23,
  Comb: 1 << 24,
  RichText: 1 << 25,
  // Button specific
  NoToggleToOff: 1 << 14,
  Radio: 1 << 15,
  Pushbutton: 1 << 16,
  // Choice specific
  Combo: 1 << 17,
  Edit: 1 << 18,
  Sort: 1 << 19,
  MultiSelect: 1 << 21,
  CommitOnSelChange: 1 << 26,
} as const;
