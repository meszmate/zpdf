# Contributing to zpdf

Thank you for your interest in contributing to zpdf! This document provides guidelines and information to make the contribution process smooth for everyone.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior by opening an issue.

---

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue on GitHub with the following information:

- **Title**: A short, descriptive summary of the issue
- **Environment**: Node.js version, OS, zpdf version
- **Steps to reproduce**: Minimal code example that triggers the bug
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened
- **PDF output**: If relevant, attach the generated PDF or a screenshot
- **Stack trace**: Include the full error message and stack trace if applicable

Before filing, please search existing issues to avoid duplicates.

### Suggesting Features

Feature requests are welcome. Please open an issue and include:

- A clear description of the feature
- The use case or problem it solves
- Example API or usage if you have one in mind
- Whether you would be willing to implement it

### Pull Requests

1. Fork the repository and create your branch from `main`
2. Make your changes following the coding standards below
3. Add or update tests for your changes
4. Ensure all tests pass and there are no lint errors
5. Write a clear PR description explaining the change
6. Submit the pull request

---

## Development Setup

### Prerequisites

- **Node.js** 16 or later
- **npm** 8 or later

### Getting Started

```bash
# Clone the repository
git clone https://github.com/meszmate/zpdf.git
cd zpdf

# Install dependencies
npm install

# Build the project
npm run build

# Run the type checker
npm run typecheck
```

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage
```

### Running Examples

```bash
# Basic PDF creation
npm run example:basic

# Tables
npm run example:tables

# Forms
npm run example:forms

# Graphics
npm run example:graphics

# Images
npm run example:images

# Merging
npm run example:merge

# Encryption
npm run example:encrypt

# Watermarks
npm run example:watermark

# Barcodes
npm run example:barcodes

# Parsing
npm run example:parse

# Accessibility / Tagged PDF
npm run example:accessibility
```

---

## Project Structure

```
src/
  annotation/       # PDF annotations (text, link, highlight, etc.)
  barcode/          # Barcode generation (Code 39, Code 128, EAN-13, QR)
  color/            # Color types (RGB, CMYK, Grayscale), named colors, conversions
  compress/         # Compression filters (deflate, inflate, ASCII85, LZW, run-length)
  core/             # Low-level PDF object model (refs, dicts, streams, object store)
  document/         # High-level document and page API (PDFDocument, PDFPage)
  font/             # Font handling (standard fonts, TrueType parsing, subsetting, embedding)
  form/             # Interactive form fields (text, checkbox, radio, dropdown, etc.)
  graphics/         # Vector graphics (path builder, gradients, patterns, transforms, clipping)
  image/            # Image embedding (JPEG, PNG with alpha)
  layers/           # Optional content groups (layers/OCG)
  metadata/         # Document info, XMP metadata, PDF/A compliance
  modify/           # PDF merge, split, watermark, and page operations
  outline/          # Bookmarks / outline tree
  parser/           # PDF parser (tokenizer, object parser, text/image extraction)
  security/         # Encryption (RC4, AES), password handling, permissions
  structure/        # Tagged PDF / accessibility (structure tree, marked content)
  table/            # Table layout, rendering, and styling
  text/             # Text layout, rendering, styles, and CMap handling
  utils/            # Shared utilities (binary readers, encoding, CRC32, math, dates)
  writer/           # PDF serializer (object writer, xref table, stream encoding)
```

---

## Coding Standards

### TypeScript

- Strict mode is enabled (`strict: true` in `tsconfig.json`)
- Use explicit types for function parameters and return values
- Prefer `interface` over `type` for object shapes
- Use `readonly` where appropriate

### Zero Dependencies

This is a zero-dependency library. Do not add any runtime dependencies. All functionality must be implemented within the library.

### Binary Data

- Use `Uint8Array` for all binary data, never `Buffer`
- This ensures the library works in browsers, Deno, and other non-Node.js runtimes
- Use the utilities in `src/utils/buffer.ts` and `src/utils/reader.ts` for binary operations

### Formatting

The project uses Prettier for code formatting:

```bash
# Check formatting
npm run format:check

# Fix formatting
npm run format
```

### Linting

ESLint is configured with TypeScript rules:

```bash
# Run linter
npm run lint

# Auto-fix issues
npm run lint:fix
```

---

## Testing Guidelines

### File Naming

Test files should be placed alongside the source or in a `tests/` directory and use the `.test.ts` extension:

```
tests/
  document.test.ts
  table.test.ts
  parser.test.ts
  security.test.ts
  ...
```

### What to Test

- **Unit tests** for individual functions and classes
- **Integration tests** for workflows (e.g., create a PDF then parse it back)
- **Edge cases**: empty inputs, maximum sizes, special characters, Unicode
- **Regression tests**: when fixing a bug, add a test that reproduces the original issue

### Round-Trip Testing

A key testing strategy is round-trip testing: create a PDF with zpdf, then parse it back and verify the content. This validates both the writer and the parser.

```typescript
import { PDFDocument, parsePdf } from 'zpdf';
import { describe, it, expect } from 'vitest';

describe('round-trip', () => {
  it('should preserve text content', async () => {
    const doc = PDFDocument.create();
    const font = doc.getStandardFont('Helvetica');
    const page = doc.addPage();
    page.drawText('Hello', { x: 50, y: 700, font, fontSize: 12 });

    const bytes = doc.save();
    const parsed = await parsePdf(bytes);

    const text = parsed.pages[0].extractText();
    expect(text.some(item => item.text.includes('Hello'))).toBe(true);
  });
});
```

---

## Pull Request Process

### Branch Naming

Use descriptive branch names with a prefix:

- `feat/table-row-spans` - New feature
- `fix/parser-xref-offset` - Bug fix
- `refactor/security-module` - Refactoring
- `docs/api-reference` - Documentation
- `test/merger-edge-cases` - Tests
- `chore/update-tsconfig` - Maintenance

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add row span support to tables
fix: correct xref offset calculation for linearized PDFs
refactor: extract stream encoding into separate module
docs: add encryption examples to README
test: add round-trip tests for form fields
chore: update TypeScript to 5.4
```

### CI Checks

All pull requests must pass:

- `npm run typecheck` - TypeScript compilation with no errors
- `npm run lint` - ESLint with no warnings or errors
- `npm run format:check` - Prettier formatting compliance
- `npm test` - All tests pass

### Review Process

1. Submit your PR with a clear description of what changed and why
2. At least one maintainer review is required
3. Address review feedback with additional commits (do not force-push during review)
4. Once approved, the PR will be squash-merged into `main`

---

## Architecture Guidelines

### Module Boundaries

Each directory under `src/` represents a distinct module. Keep dependencies between modules minimal and well-defined. The general dependency direction is:

```
utils, core  <--  font, color, compress  <--  graphics, text, image  <--  document  <--  writer
                                                                          ^
                                                                          |
                                                          table, form, annotation, barcode,
                                                          outline, layers, structure, metadata
                                                                          |
                                                                          v
                                                                   parser, modify, security
```

### No Circular Dependencies

Circular imports are not allowed. If two modules need to reference each other, extract the shared types into `core/types.ts` or a common utility module.

### PDF Spec Compliance

- Follow the PDF 1.7 specification (ISO 32000-1:2008) as the primary reference
- Document any deviations or limitations in code comments
- Use correct PDF operator names and dictionary key names
- Validate output with multiple PDF viewers (Adobe Reader, Chrome, Firefox, Preview)

---

## Release Process

Releases are managed by the maintainers:

1. All changes are merged into `main`
2. Version is bumped in `package.json` following [semver](https://semver.org/):
   - **patch** (1.0.x) - Bug fixes and minor improvements
   - **minor** (1.x.0) - New features, backward-compatible
   - **major** (x.0.0) - Breaking API changes
3. A git tag is created (`vX.Y.Z`)
4. The package is published to npm via `npm publish`
5. A GitHub release is created with a changelog

---

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/meszmate/zpdf/discussions) on GitHub
- **Bugs**: Open an [Issue](https://github.com/meszmate/zpdf/issues)
- **Chat**: Check existing discussions and issues for context before asking

Thank you for contributing to zpdf!
