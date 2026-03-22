# Contributing to TransformationSwiftUI

Thank you for considering a contribution! This guide explains how to get involved.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Submitting Pull Requests](#submitting-pull-requests)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Testing](#testing)
- [Commit Messages](#commit-messages)
- [Branching Strategy](#branching-strategy)
- [Releasing](#releasing)

---

## Code of Conduct

By participating in this project you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before contributing.

---

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/kanchanproseth/TransformationSwiftUI.git
   cd TransformationSwiftUI
   ```
3. **Build** to verify everything compiles:
   ```bash
   swift build
   ```
4. **Run tests**:
   ```bash
   swift test
   ```

---

## How to Contribute

### Reporting Bugs

- Search [existing issues](../../issues) first to avoid duplicates.
- Open a new issue using the **Bug Report** template.
- Include:
  - macOS version and Swift toolchain version (`swift --version`)
  - A minimal UIKit snippet or storyboard that triggers the problem
  - The full CLI output or error message
  - The expected vs actual generated SwiftUI code

### Suggesting Features

- Open a new issue using the **Feature Request** template.
- Describe the UIKit pattern you want supported and the SwiftUI idiom you expect the tool to emit.

### Submitting Pull Requests

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-improvement
   ```
2. Make your changes (see [Code Style](#code-style) and [Testing](#testing)).
3. Push your branch and open a pull request against `main`.
4. Fill in the **Pull Request** template — link related issues, describe what changed and why.
5. A maintainer will review your PR. Expect feedback within a few days.

**PR checklist:**
- [ ] Code compiles with `swift build`
- [ ] All existing tests pass with `swift test`
- [ ] New behaviour is covered by at least one test
- [ ] CHANGELOG.md entry added under `Unreleased`
- [ ] No force-unwraps introduced without a documented rationale
- [ ] SPDX licence header present in every new `.swift` file

---

## Development Setup

| Tool | Version |
|---|---|
| macOS | 13.0+ |
| Swift | 5.9+ |
| Xcode | 15.0+ (optional, for IDE support) |

The project has a single external dependency — `apple/swift-syntax` — which is fetched automatically by SPM.

```bash
swift package resolve   # fetch dependencies
swift build             # debug build
swift build -c release  # release build
```

---

## Code Style

- **Naming**: PascalCase for types and protocols; camelCase for methods and properties.
- **Indentation**: 4 spaces (no tabs).
- **Line length**: prefer ≤ 120 characters.
- **Access control**: use the narrowest level that makes the API work (`private` > `fileprivate` > `internal` > `public`).
- **Avoid force-unwrap** (`!`) unless the invariant is documented inline.
- **Prefer `guard` over nested `if`** for early returns.
- **SPDX header**: every new `.swift` file must start with:
  ```swift
  // SPDX-License-Identifier: MIT
  //
  // FileName.swift
  // Part of the TransformationSwiftUI project
  //
  // Copyright (c) 2026 Kan Chanproseth and contributors
  //
  // Description: One-line description of this file's purpose.
  //
  ```

---

## Testing

Tests live in `Tests/TransformationSwiftUITests/`. The project uses Swift's built-in `XCTest` framework.

```bash
swift test                            # run all tests
swift test --filter UIKitElementType  # run a specific test class
```

When adding new functionality, please add tests that cover:
- Happy path: the expected SwiftUI output for a known UIKit input.
- Edge cases: empty inputs, unknown element types, missing constraints.

---

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

[optional body]

[optional footer]
```

Common types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.

Examples:
```
feat(renderer): add DatePicker renderer for UIDatePicker
fix(parser): handle optional chaining in addSubview calls
docs(readme): document --create-project flag
test(generator): add tests for visibility state generation
```

---

## Branching Strategy

- `main` is the only long-lived branch.
- All work happens on short-lived feature branches.
- Open PRs targeting `main`; keep branches focused and easy to review.
- Prefer squash merges to keep history clean.
- Releases are created from tags on `main`.

---

## Releasing

Releases are tagged on `main` following [Semantic Versioning](https://semver.org/):

- `MAJOR` — breaking changes to the public API
- `MINOR` — new features, backwards-compatible
- `PATCH` — bug fixes, backwards-compatible

A maintainer will:
1. Update `CHANGELOG.md` (move `Unreleased` to a dated version section).
2. Create a git tag: `git tag -s v1.2.3 -m "Release v1.2.3"`.
3. Push the tag: `git push origin v1.2.3`.
4. Create a GitHub Release from the tag, copying the changelog entry.

---

Thank you for contributing!
