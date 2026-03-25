# Roadmap

> **Note:** This roadmap reflects our current thinking and priorities. It is subject to change — items may be added, reprioritised, or removed as the project evolves and the community provides feedback.
>
> Have a suggestion? [Open a discussion](https://github.com/kanchanproseth/TransformationSwiftUI/discussions) or [file a feature request](https://github.com/kanchanproseth/TransformationSwiftUI/issues/new?template=feature_request.md).

---

## Status legend

| Symbol | Meaning |
|---|---|
| ✅ | Shipped |
| 🔨 | In progress |
| 📋 | Planned |
| 🔬 | Research & exploration (may or may not ship) |

---

## Current: v0.0.1 — Foundation ✅

The core five-phase conversion pipeline is complete and publicly released.

- ✅ Swift source parsing (SwiftSyntax)
- ✅ Storyboard & XIB parsing
- ✅ Custom UIView / UIControl detection with transitive inheritance resolution
- ✅ Layout pattern inference (VStack / HStack / ZStack from Auto Layout constraints)
- ✅ Navigation flow generation (`AppFlowView.swift`)
- ✅ AI-assisted conversion (Anthropic, OpenAI, Perplexity, local/Ollama)
- ✅ RAG indexing for large-project context
- ✅ Business logic annotations
- ✅ Animation detection
- ✅ CLI + SPM library targets
- ✅ GitHub Actions CI & automated release pipeline

---

## Near term — Core accuracy improvements 🔨

The pipeline structure is in place. The next focus is improving the quality of what it generates.

### AI prompt improvements
Refine the prompts used for AI-assisted conversion to produce more accurate, idiomatic SwiftUI output for complex screens. This includes better context injection, few-shot examples, and chain-of-thought formatting for layout-heavy controllers.

### Nested view accuracy
The current engine handles shallow hierarchies well. This milestone targets deeply nested views — scroll views containing stack views containing custom cells, tab-embedded navigation controllers, and other multi-level compositions.

### Navigation accuracy
Improve edge-case handling in `NavigationFlowGenerator`: conditional navigation, programmatic flows with multiple branches, deep-link targets, and `UINavigationController` push/pop state.

### Custom view accuracy
Strengthen the `CustomComponentAnalyzer` and `CustomComponentDefinitionGenerator` for components with complex internal layouts, protocol conformances, delegate patterns, and custom `layoutSubviews` overrides.

---

## Medium term — Mac app 📋

A native macOS app that wraps the conversion engine with a GUI, making the tool accessible to developers who prefer a point-and-click workflow over the command line.

**Planned capabilities:**
- Project picker — browse to a UIKit project directory
- Conversion dashboard — live log output, per-file status indicators
- File diff view — side-by-side comparison of UIKit input and SwiftUI output before writing to disk
- AI provider configuration panel — set API keys and model preferences without editing environment variables
- One-click scaffold export — trigger `--create-project` from the UI
- Drag-and-drop single-file conversion for quick experiments

---

## Medium term — Training dataset 📋

Build and publish a curated dataset of UIKit → SwiftUI conversion pairs to enable fine-tuning and benchmarking.

**Planned work:**
- Collect UIKit source examples spanning common patterns (login screens, lists, detail views, settings, dashboards)
- Pair each example with a hand-verified SwiftUI equivalent
- Establish automated accuracy metrics (compilability, structural similarity, state binding coverage)
- Use the dataset to measure and improve AI prompt quality
- Explore publishing the dataset openly for the community

---

## Medium term — Website 📋

A dedicated project website to improve discoverability and provide documentation outside of GitHub.

**Planned content:**
- Live demo — paste UIKit code, see the SwiftUI output in-browser
- Getting started guide
- Full API documentation (generated from `docs/API.md`)
- Conversion showcase — before/after examples for common UIKit patterns
- Blog / release notes feed

---

## Research — Business logic extraction 🔬

Currently the pipeline annotates detected business logic as `// TODO:` comments in the generated output rather than converting it. This item explores whether the logic can be meaningfully extracted and relocated.

**Questions to answer:**
- Can `IBAction` handlers be automatically separated from view mutation code?
- Is it feasible to identify which logic belongs in a ViewModel vs a View vs a Coordinator?
- Can the tool produce a skeleton ViewModel alongside the View, with bindings pre-wired?

This is exploratory. Outcome may influence or merge with the MVC → MVVM item below.

---

## Research — MVC to MVVM conversion 🔬

Today the tool converts UIKit view structure to SwiftUI view structure. This item explores going further: converting the underlying architecture from MVC to MVVM.

**Questions to answer:**
- Can the tool reliably identify which `UIViewController` code is view logic vs business logic?
- Is automated `@Observable` / `ObservableObject` ViewModel generation feasible?
- How should `@Binding` and `@StateObject` wiring be handled across screen boundaries?
- What is the right scope — whole-project refactor vs per-screen opt-in?

This is deep research territory. It may ship as a separate tool or an optional post-processing pass rather than part of the core pipeline.

---

## How to influence the roadmap

The priorities above reflect the current maintainer's view. Community input matters.

- **+1 an existing item** — react to the relevant GitHub issue with 👍
- **Propose something new** — [open a feature request](https://github.com/kanchanproseth/TransformationSwiftUI/issues/new?template=feature_request.md)
- **Help build it** — see [CONTRIBUTING.md](CONTRIBUTING.md) for how to get involved

---

*Last updated: March 2026.*
