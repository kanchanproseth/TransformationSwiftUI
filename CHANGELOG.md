# Changelog

All notable changes to TransformationSwiftUI are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

_Nothing yet._

---

## [0.0.1] — 2026-03-21

### Added
- Five-phase UIKit → SwiftUI conversion pipeline
- Swift source parsing via SwiftSyntax (`ViewControllerVisitor`, `ViewHierarchyVisitor`, `AutoLayoutVisitor`)
- Storyboard and XIB parsing via Foundation `XMLDocument` (`StoryboardParser`, `IBElementMapper`, `IBConstraintMapper`, `IBSegueMapper`)
- Custom UIView / UIControl subclass detection with multi-pass transitive inheritance resolution (`CustomComponentAnalyzer`, `CustomComponentRegistry`)
- Layout pattern inference from Auto Layout constraints (`LayoutPatternEngine`) — infers `VStack`, `HStack`, `ZStack`
- Navigation flow generation from storyboard segue graphs (`NavigationFlowGenerator`) — produces `AppFlowView.swift`
- Supported segue translations: `show`/`push` → `NavigationLink`, `presentation` → `.sheet` / `.fullScreenCover`, `relationship` → `TabView`, `embed` → inline child view, `unwind` → `@Environment(\.dismiss)`
- Property-aware rendering: label text, button titles, image names, placeholder strings, stack-view axis
- Animation detection (`AnimationVisitor`) — `UIView.animate`, `CABasicAnimation`, `CAKeyframeAnimation`, `CASpringAnimation`, `UIViewPropertyAnimator`
- Business logic annotations (`BusinessLogicVisitor`) — `IBAction` bindings, target-action patterns, `performSegue`, `present`, `dismiss`, `push`
- Visibility logic tracking (`VisibilityLogicVisitor`) — `isHidden`, `alpha` mutations
- Custom drawing detection (`DrawingCommandVisitor`) — Core Graphics command identification in `draw(_:)` overrides
- AI-assisted conversion layer (`AIConversionLayer`) with heuristic complexity scoring
- Cloud AI providers: Anthropic Claude (default `claude-sonnet-4-20250514`), OpenAI (default `gpt-4o`), Perplexity (default `sonar`)
- Local AI provider for Ollama / any OpenAI-compatible endpoint (default `deepseek-r1:1.5b`)
- RAG indexing (`RAGIndex`) for large-project context retrieval
- Xcode project scaffold generation (`ProjectScaffoldGenerator`) via `--create-project` / `--app-name`
- AI smoke-test mode (`--ai-smoke-test` / `--ai-smoke-output`) for provider connectivity checks
- Deduplication: Swift-source version takes priority when a controller exists in both source and storyboard
- Full environment-variable configuration (no config files required)
- Swift Package Manager library target (`TransformationSwiftUI`) and CLI target (`TransformationSwiftUICLI`)
- Unit tests for renderers, code generator, and layout engine (`UIKitElementTypeTests`)

[Unreleased]: https://github.com/kanchanproseth/TransformationSwiftUI/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/kanchanproseth/TransformationSwiftUI/releases/tag/v0.0.1
