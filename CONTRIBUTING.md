# Contributing to zpdf

Thank you for your interest in contributing to zpdf! This document provides guidelines and information to help you get started.

## Getting Started

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.15.0 or later, it needs to be compatible with the latest version
- Git
- A PDF viewer for verifying output (any standard viewer works)

### Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/<your-username>/zpdf.git
   cd zpdf
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run the tests:
   ```bash
   zig build test
   ```

4. Try an example to verify everything works:
   ```bash
   zig build run-create_basic
   ```

### Running Examples

All examples are in the `examples/` directory and can be run with:

```bash
zig build run-create_basic
zig build run-create_tables
zig build run-create_graphics
zig build run-create_forms
zig build run-create_images
zig build run-merge_pdfs
zig build run-encrypt_pdf
zig build run-watermark
zig build run-barcodes
zig build run-parse_pdf
zig build run-accessibility
```

## Project Structure

```
zpdf/
├── src/
│   ├── root.zig              # Public API exports
│   ├── core/                 # PDF object model (objects, references, xref)
│   ├── writer/               # PDF file serialization and output
│   ├── parser/               # PDF file parsing and tokenization
│   ├── document/             # High-level Document and Page API
│   ├── text/                 # Text layout, line breaking, text drawing
│   ├── font/                 # Font metrics, encoding, standard 14 fonts
│   ├── graphics/             # Drawing primitives, paths, shapes, transforms
│   ├── image/                # Image embedding (JPEG, PNG, raw)
│   ├── color/                # Color spaces (RGB, CMYK, grayscale)
│   ├── table/                # Table layout and rendering
│   ├── security/             # Encryption (RC4, AES), permissions, passwords
│   ├── form/                 # AcroForms (text fields, checkboxes, dropdowns)
│   ├── annotation/           # Annotations (links, notes, highlights)
│   ├── barcode/              # Barcode generation (Code128, QR, EAN, etc.)
│   ├── outline/              # Bookmarks / document outline
│   ├── layers/               # Optional Content Groups (OCG / layers)
│   ├── structure/            # Tagged PDF / accessibility (PDF/UA)
│   ├── metadata/             # Document metadata and XMP
│   ├── compress/             # Deflate compression for streams
│   ├── modify/               # PDF modification (merge, split, watermark)
│   └── utils/                # Shared utilities (formatting, math, buffers)
├── tests/                    # Unit and integration tests
├── examples/                 # Example applications
├── build.zig                 # Build configuration
└── build.zig.zon             # Package manifest
```

## Code Guidelines

### Zero Dependencies

zpdf has no external dependencies and must stay that way. All functionality must be implemented using only the Zig standard library. This includes compression, encryption, font metrics, and barcode generation.

### Memory Management

- Use `std.mem.Allocator` everywhere -- never use a global or default allocator
- Every allocation must have a corresponding deallocation
- Prefer arena allocators for temporary per-operation work
- All public types must provide `init(allocator)` and `deinit()` methods
- Document ownership semantics clearly

### Error Handling

- Use Zig's error unions (`!T`) for all fallible operations
- Use `try` / `catch` for propagation and handling
- Define specific error sets rather than using `anyerror` where practical
- Never use `@panic` in library code -- panics are reserved for truly unreachable states only
- Return meaningful errors that help users diagnose issues

### Style

- Follow the existing code style in the project
- Use the Zig standard library naming conventions (`camelCase` for functions, `snake_case` for variables)
- Keep functions focused and reasonably sized
- Use descriptive names over comments where possible
- Prefer `const` over `var` whenever possible

### PDF Spec Compliance

zpdf targets **PDF 1.7 (ISO 32000-1:2008)**. When implementing features:

- Reference the relevant section of the PDF specification
- Note the spec section in code comments for non-trivial implementations
- Ensure generated PDFs are valid (test with multiple PDF viewers)
- Follow the spec's naming conventions for PDF operators and dictionary keys

## Testing Guidelines

### General

- Tests live in the `tests/` directory
- Add tests for all new functionality
- Run the full test suite before submitting: `zig build test`

### Round-Trip Testing

For PDF features, use round-trip testing where possible:

1. Create a PDF document programmatically
2. Serialize it to bytes
3. Parse the bytes back into a document
4. Verify the parsed data matches the original

This ensures both the writer and parser are correct and consistent.

### Test Coverage

- **Unit tests**: Test individual functions and types in isolation
- **Integration tests**: Test full document creation and parsing workflows
- **Edge cases**: Empty documents, large files, special characters, boundary values
- **Error paths**: Verify that invalid input produces appropriate errors

## Submitting Changes

### Branch Naming

Create a branch from `main` using one of these prefixes:

```bash
git checkout -b feat/add-qr-codes
git checkout -b fix/text-wrapping-overflow
git checkout -b refactor/simplify-xref-table
git checkout -b docs/update-api-reference
git checkout -b test/add-parser-edge-cases
git checkout -b chore/update-build-config
```

### Commit Messages

Use conventional commits:

```
feat: add QR code barcode generation
fix: correct text positioning with custom fonts
refactor: simplify cross-reference table building
docs: add table API examples
test: add round-trip tests for encrypted PDFs
chore: update minimum Zig version
```

### Pull Request Process

1. Ensure all tests pass (`zig build test`)
2. Ensure the project builds without warnings (`zig build`)
3. Ensure examples still run correctly
4. Provide a clear description of what the PR does and why
5. Link related issues if applicable
6. Keep PRs focused -- one feature or fix per PR

## Architecture

### Module Dependency Graph

The library follows a layered architecture. Lower layers must not depend on higher layers.

```
Layer 1 (Foundation):    utils, core
Layer 2 (Primitives):    compress, font, color
Layer 3 (Drawing):       graphics, text, image
Layer 4 (Document):      document (Page, Document)
Layer 5 (High-level):    writer, table, form, annotation, barcode,
                         outline, layers, structure, metadata
Layer 6 (Operations):    parser, modify, security
```

Dependency flow:

```
utils/core  <--  compress/font/color  <--  graphics/text/image
                                                   |
                                                   v
parser/modify/security  -->  document  <--  writer/table/form/annotation/
                                            barcode/outline/layers/
                                            structure/metadata
```

When adding new modules, respect these dependency boundaries. If a new module needs something from a higher layer, consider refactoring to push shared logic down.

## License

By contributing to zpdf, you agree that your contributions will be licensed under the [MIT License](LICENSE).
