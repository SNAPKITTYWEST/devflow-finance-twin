# Apple Design System Parser Guide

## Overview

The Apple Design System Parser is a Swift utility for reverse-engineering and parsing Apple's design tokens from HTML/CSS payloads.

## Installation

```bash
swift build
```

## Usage Examples

### Parse HTML File
```bash
./apple-parser parse index.html
```

### Extract Hex Colors
```bash
./apple-parser extract styles.css
```

### Resolve Design Token
```bash
./apple-parser resolve "Primary Background"
./apple-parser resolve "Apple Blue (Link)" --dark
```

## API Usage

```swift
import AppleDesignSystem

let html = try String(contentsOfFile: "page.html")
let result = AppleDesignHTMLParser.parsePayload(html)

for (token, value) in result.colorTokens() {
    print("\(token): \(value)")
}
```

## Commands

### parse
Parse an HTML or CSS file and extract all color token declarations.

**Usage:** `apple-parser parse <file>`

**Output:** Displays parsed declarations with variable names and values.

### extract
Extract all hex color values from a file.

**Usage:** `apple-parser extract <file>`

**Output:** List of all hex colors found in the file.

### resolve
Resolve a design token name to its corresponding color value.

**Usage:** `apple-parser resolve <token-name> [--dark]`

**Options:**
- `--dark`: Resolve token for dark mode appearance

**Output:** Token name followed by resolved color value.

### validate
Validate color declarations in a file and generate a validation report.

**Usage:** `apple-parser validate <file>`

**Output:** Report showing count of valid and invalid declarations.

## Features

- Parses HTML/CSS payloads containing Apple design tokens
- Extracts hex color values using pattern matching
- Resolves design tokens with light/dark mode support
- Validates color format declarations
- Comprehensive error handling
- Human-readable CLI interface

## Requirements

- Swift 5.5 or later
- Foundation framework (included in Swift standard library)

## Building

```bash
swift build -c release
```

The compiled binary will be available at `.build/release/apple-parser`.

## Example Workflow

1. Export Apple design system HTML from Figma or design tool
2. Run parser: `apple-parser parse design-export.html`
3. Extract specific colors: `apple-parser extract design-export.html`
4. Validate color declarations: `apple-parser validate design-export.html`
5. Resolve individual tokens: `apple-parser resolve "Primary Background" --dark`
