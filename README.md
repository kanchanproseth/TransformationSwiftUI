# TransformationSwiftUI

![Platform](https://img.shields.io/badge/platform-macOS-lightgray)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-blue)
![SPM](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen)

A command-line tool that automatically converts UIKit projects — including Auto Layout constraints, storyboards, XIBs, custom UIView subclasses, and full navigation flows — into idiomatic SwiftUI views wired together with `NavigationStack`, `TabView`, `NavigationLink`, and modal presentations.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Library Usage](#library-usage)
  - [Basic Conversion](#basic-conversion)
  - [Custom Component Detection](#custom-component-detection)
  - [Storyboard and XIB Support](#storyboard-and-xib-support)
  - [Navigation Flow Detection](#navigation-flow-detection)
  - [AI-Assisted Conversion](#ai-assisted-conversion)
  - [RAG Indexing](#rag-indexing)
- [How It Works](#how-it-works)
- [Output](#output)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Dependencies](#dependencies)
- [Contributing](#contributing)
- [Code of Conduct](#code-of-conduct)
- [Security](#security)
- [Support](#support)
- [License](#license)

---

## Features

- **Swift Source Parsing** — Analyses UIViewController subclasses using SwiftSyntax to extract view hierarchies and Auto Layout constraints
- **Storyboard & XIB Support** — Parses `.storyboard` and `.xib` XML files and converts them through the same pipeline as Swift source
- **Custom Component Detection** — Discovers custom `UIView`/`UIControl` subclasses with full transitive inheritance resolution; generates standalone SwiftUI wrappers for each
- **Navigation Flow Detection** — Extracts the full segue graph from storyboard files and generates a top-level `AppFlowView.swift` that wires every screen together with `NavigationStack`, `TabView`, `NavigationLink`, `.sheet`, and `.fullScreenCover`
- **Layout Pattern Engine** — Infers `VStack`, `HStack`, and `ZStack` arrangements from constraint relationships using graph analysis
- **Property-Aware Rendering** — Uses actual text, titles, image names, placeholders, and axis values from Interface Builder directly in the generated code
- **AI-Assisted Conversion** — Optionally routes complex layouts to a cloud LLM (Anthropic Claude, OpenAI, Perplexity) or a locally-hosted model for higher-quality output
- **RAG Indexing** — Retrieval-augmented generation for large projects; supplies relevant existing SwiftUI snippets as context to the AI layer
- **Deduplication** — When both Swift source and a storyboard reference the same view controller, the Swift source always takes priority

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13.0+ |
| Swift | 5.9+ |
| Xcode | 15.0+ (for development) |

---

## Installation

### Swift Package Manager

Clone the repository and build with the Swift Package Manager:

```bash
git clone https://github.com/your-org/TransformationSwiftUI.git
cd TransformationSwiftUI
swift build -c release
```

The compiled binary is placed at `.build/release/TransformationSwiftUICLI`.

You can copy it to a location on your `PATH`:

```bash
cp .build/release/TransformationSwiftUICLI /usr/local/bin/TransformationSwiftUICLI
```

---

## Usage

### Library Usage

Add the package to your `Package.swift` dependencies and import it:

```swift
.package(url: "https://github.com/your-org/TransformationSwiftUI.git", from: "1.0.0")
```

```swift
import TransformationSwiftUI

let exitCode = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/your/UIKitProject"
)
```

**Xcode UI integration (minimal):**

1. In Xcode, go to `File` → `Add Package Dependencies...`.
2. Paste the repository URL.
3. Select the `TransformationSwiftUI` product and add it to your app target.
4. Import the module and call the runner (as above).

**Tiny example (inside an app or script):**

```swift
import TransformationSwiftUI

let exitCode = TransformationSwiftUIRunner.run(
    projectPath: "/Users/me/Projects/LegacyUIKitApp",
    aiConfig: AIConversionConfig(enabled: false, minimumComplexity: 12, forceAI: false)
)
print("Exit code: \(exitCode)")
```

### Basic Conversion

Point the tool at the root of any UIKit project:

```bash
TransformationSwiftUICLI /path/to/your/UIKitProject
```

Generated SwiftUI files are written to a `SwiftUIMigrated/` folder inside the target project.

```bash
swift run TransformationSwiftUICLI /path/to/your/UIKitProject
```

### Custom Component Detection

The tool automatically performs a multi-pass analysis to discover every `UIView` and `UIControl` subclass in the project, including transitive inheritance chains.

**Example input:**

```swift
class RoundedButton: UIButton { ... }
class PrimaryButton: RoundedButton { ... }
```

**Output:** `PrimaryButtonView.swift` and `RoundedButtonView.swift` are generated with their internal structure mapped to SwiftUI, and any view controller that references them uses the generated wrappers.

### Storyboard and XIB Support

The tool discovers all `.storyboard` and `.xib` files alongside Swift source. Each view controller scene becomes a SwiftUI view file:

- Label text, button titles, image names, and placeholders are read directly from the XML
- Stack view axis and spacing are honoured
- Auto Layout constraints are translated to `.frame`, `.padding`, and alignment modifiers
- Custom classes referenced in Interface Builder are resolved against the detected component registry

> Swift source takes priority: if a view controller is found in both a `.storyboard` and a `.swift` file, the Swift-parsed version is used.

### Navigation Flow Detection

The tool analyses every `.storyboard` file for segue connections and builds a navigation graph. A single `AppFlowView.swift` is written to `SwiftUIMigrated/` and acts as the app entry point, mirroring the flow from UIKit.

**Supported segue kinds:**

| UIKit segue kind | SwiftUI equivalent |
|---|---|
| `show` / `push` | `NavigationLink` inside a `NavigationStack` |
| `presentation` / `modal` | `.sheet` modifier |
| `presentation` (fullScreen style) | `.fullScreenCover` modifier |
| `relationship` on `UITabBarController` | `TabView` with labelled tabs |
| `embed` | Inline child view |
| `unwind` | `@Environment(\.dismiss)` |

**Example:** a storyboard with a login screen that pushes to a dashboard, which is embedded in a tab bar, produces:

```swift
import SwiftUI

struct AppFlowView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardViewControllerView()
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                ProfileViewControllerView()
            }
            .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}
```

Each individual view file also receives `@State` properties and `.sheet` / `.fullScreenCover` / `NavigationLink` modifiers for any outgoing segues it owns.

### AI-Assisted Conversion

The tool can route complex view controllers to a cloud or local language model. Set `TRANSFORMATION_SWIFTUI_AI_ENABLED=1` and supply one API key. Cloud providers take priority over local when both are configured.

#### Cloud providers

**Anthropic (Claude)**
```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY=sk-ant-api03-...
# Optional overrides:
# export TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL=claude-opus-4-20250514
# export TRANSFORMATION_SWIFTUI_ANTHROPIC_ENDPOINT=https://api.anthropic.com/v1/messages
TransformationSwiftUICLI /path/to/your/UIKitProject
```

**OpenAI**
```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_OPENAI_API_KEY=sk-...
# Optional overrides:
# export TRANSFORMATION_SWIFTUI_OPENAI_MODEL=gpt-4o
# export TRANSFORMATION_SWIFTUI_OPENAI_ENDPOINT=https://api.openai.com/v1/chat/completions
TransformationSwiftUICLI /path/to/your/UIKitProject
```

**Perplexity**
```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY=pplx-...
# Optional overrides:
# export TRANSFORMATION_SWIFTUI_PERPLEXITY_MODEL=sonar
# export TRANSFORMATION_SWIFTUI_PERPLEXITY_ENDPOINT=https://api.perplexity.ai/chat/completions
TransformationSwiftUICLI /path/to/your/UIKitProject
```

#### Local provider (Ollama / self-hosted)
```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_AI_ENDPOINT=http://localhost:11434/api/generate
# export TRANSFORMATION_SWIFTUI_AI_MODEL=deepseek-r1:1.5b
TransformationSwiftUICLI /path/to/your/UIKitProject
```

#### Default models

| Provider | Default model |
|---|---|
| Anthropic | `claude-sonnet-4-20250514` |
| OpenAI | `gpt-4o` |
| Perplexity | `sonar` |
| Local | `deepseek-r1:1.5b` |

Run a quick connectivity check without converting a project:

```bash
TransformationSwiftUICLI --ai-smoke-test "Convert a UIButton to SwiftUI."
```

Write the AI response to a file:

```bash
TransformationSwiftUICLI --ai-smoke-test "Convert a UIButton to SwiftUI." \
  --ai-smoke-output /tmp/ai-output.swift
```

### RAG Indexing

For large projects, enable retrieval-augmented generation to supply relevant existing SwiftUI code as context:

```bash
export TRANSFORMATION_SWIFTUI_RAG_ENABLED=1
TransformationSwiftUICLI /path/to/your/UIKitProject
```

---

## How It Works

The tool runs in five sequential phases:

```
Phase 1 — Custom Component Discovery
  FileScanner finds all .swift files.
  CustomComponentAnalyzer performs multi-pass inheritance resolution.
  A CustomComponentRegistry is built containing every UIView/UIControl subclass.

Phase 2 — Custom Component Code Generation
  A SwiftUI View struct is generated for each discovered component.

Phase 3 — Swift Source Parsing
  SwiftParser visits each .swift file.
  ViewControllerVisitor identifies UIViewController subclasses.
  ViewHierarchyVisitor builds the view tree (addSubview / addArrangedSubview).
  AutoLayoutVisitor extracts NSLayoutConstraint declarations.
  LayoutPatternEngine infers VStack/HStack/ZStack arrangements.
  SwiftUICodeGenerator produces the final SwiftUI output.

Phase 4 — Interface Builder Parsing
  FileScanner finds all .storyboard and .xib files.
  StoryboardParser reads the XML, resolves outlet names, element types,
  and constraints through IBElementMapper and IBConstraintMapper.
  The same SwiftUICodeGenerator pipeline produces the output.
  Controllers already generated in Phase 3 are skipped.

Phase 5 — Navigation Flow Generation
  StoryboardParser.parseNavigationGraph extracts the segue graph from
  every .storyboard file: push/sheet/fullScreenCover/tab/embed/unwind edges
  and NavigationStack / TabBar container controllers.
  Graphs from multiple storyboards are merged (deduplicating by
  source+destination+kind).
  NavigationFlowGenerator emits AppFlowView.swift — the SwiftUI entry point
  that mirrors the UIKit navigation structure.
```

---

## Output

All generated files are written to `<project-path>/SwiftUIMigrated/`.

| Input | Output |
|---|---|
| `LoginViewController.swift` | `LoginViewControllerView.swift` |
| `RoundedButton.swift` (custom UIButton) | `RoundedButtonView.swift` |
| `Main.storyboard` (ProfileViewController scene) | `ProfileViewControllerView.swift` |
| `CardView.xib` | `CardViewView.swift` |
| `Main.storyboard` (segue graph) | `AppFlowView.swift` |

**Example output for a view controller with a label, text field, and button:**

```swift
import SwiftUI

struct LoginViewControllerView: View {
    @State private var emailTextFieldText: String = ""

    var body: some View {
        VStack {
            Text("Welcome Back")
            TextField("Email", text: $emailTextFieldText)
            Button("Sign In") { }
        }
    }
}

struct LoginViewControllerView_Previews: PreviewProvider {
    static var previews: some View {
        LoginViewControllerView()
    }
}
```

---

## Configuration

All configuration is done through environment variables.

### AI Conversion

| Variable | Default | Description |
|---|---|---|
| `TRANSFORMATION_SWIFTUI_AI_ENABLED` | `0` | Set to `1` to enable AI-assisted conversion |
| `TRANSFORMATION_SWIFTUI_AI_ENDPOINT` | — | URL of the local LLM endpoint |
| `TRANSFORMATION_SWIFTUI_AI_MODEL` | `deepseek-r1` | Model name to request |
| `TRANSFORMATION_SWIFTUI_AI_THRESHOLD` | `10` | Complexity score above which AI is invoked |

### RAG Indexing

| Variable | Default | Description |
|---|---|---|
| `TRANSFORMATION_SWIFTUI_RAG_ENABLED` | `0` | Set to `1` to enable RAG context |
| `TRANSFORMATION_SWIFTUI_RAG_TOP_K` | `4` | Number of retrieved chunks per query |
| `TRANSFORMATION_SWIFTUI_RAG_CHUNK_SIZE` | `1200` | Maximum tokens per code chunk |
| `TRANSFORMATION_SWIFTUI_RAG_CHUNK_OVERLAP` | `200` | Overlap tokens between adjacent chunks |

---

## Project Structure

```
TransformationSwiftUI/
├── Package.swift
├── Sources/
│   ├── TransformationSwiftUI/
│   │   ├── TransformationSwiftUIRunner.swift # Public facade for running the pipeline
│   │   ├── SwiftUICodeGenerator.swift        # Rule-based SwiftUI code generation
│   │   ├── SwiftUIRenderers.swift            # Per-element rendering strategies
│   │   ├── CustomComponentRenderer.swift     # SwiftUI wrappers for custom UIView subclasses
│   │   ├── NavigationFlowGenerator.swift     # Generates AppFlowView.swift from navigation graph
│   │   ├── AIConversionLayer.swift           # AI routing and complexity scoring
│   │   ├── LocalAIConversionProvider.swift   # HTTP client for local LLM endpoints
│   │   ├── RAGIndex.swift                    # Retrieval-augmented generation index
│   │   ├── Analyzer/
│   │   │   ├── ViewControllerVisitor.swift   # Discovers UIViewController subclasses
│   │   │   ├── ViewHierarchyVisitor.swift    # Builds view tree from addSubview calls
│   │   │   ├── AutoLayoutVisitor.swift       # Extracts NSLayoutConstraint declarations
│   │   │   ├── LayoutPatternEngine.swift     # Infers VStack/HStack/ZStack from constraints
│   │   │   ├── UIKitComponentVisitor.swift   # Finds UIKit element declarations
│   │   │   ├── CustomComponentVisitor.swift  # Discovers custom UIView/UIControl subclasses
│   │   │   ├── CustomComponentAnalyzer.swift # Multi-pass inheritance chain resolution
│   │   │   └── PropertyExtractorVisitor.swift# Extracts exposed properties from custom views
│   │   ├── Models/
│   │   │   ├── UIElementNode.swift           # View tree node with type and properties
│   │   │   ├── UIKitElementType.swift        # Enum of supported UIKit component types
│   │   │   ├── LayoutConstraint.swift        # Auto Layout constraint model
│   │   │   ├── ViewControllerModel.swift     # Root model: view hierarchy + navigation metadata
│   │   │   ├── NavigationGraph.swift         # Segue graph: edges, containers, entry point
│   │   │   ├── CustomComponentModel.swift    # Discovered custom component with inheritance chain
│   │   │   └── CustomComponentRegistry.swift # Registry for type resolution
│   │   ├── Parser/
│   │   │   ├── SwiftParser.swift             # Orchestrates Swift source file parsing
│   │   │   ├── StoryboardParser.swift        # Parses .storyboard and .xib XML files; navigation graph extraction
│   │   │   ├── IBElementMapper.swift         # Maps IB XML elements to UIKitElementType
│   │   │   ├── IBConstraintMapper.swift      # Converts IB constraints to LayoutConstraint
│   │   │   └── IBSegueMapper.swift           # Maps IB segue kind strings to SegueKind
│   │   └── Scanner/
│   │       └── FileScanner.swift             # Discovers .swift, .storyboard, .xib files
│   └── TransformationSwiftUICLI/
│       └── main.swift                        # CLI entry point; delegates to the runner
└── Tests/
    └── TransformationSwiftUITests/
        └── UIKitElementTypeTests.swift       # Unit tests for renderers, generator, and layout engine
```

---

## Dependencies

| Package | Purpose |
|---|---|
| [swift-syntax](https://github.com/apple/swift-syntax) | Swift AST parsing for source analysis (SwiftSyntax + SwiftParser products) |

No other external dependencies. Storyboard and XIB parsing uses `Foundation`'s built-in `XMLDocument`.

---

## Contributing

Contributions are welcome. Please read the contribution guidelines before opening a pull request.

See `CONTRIBUTING.md` for details.

## Code of Conduct

We follow the Contributor Covenant Code of Conduct. Please read it before participating.

See `CODE_OF_CONDUCT.md` for details.

## Security

If you discover a security issue, please report it responsibly.

See `SECURITY.md` for details.

## Support

For questions and help, use Discussions. For bugs and feature requests, open an issue.

See `SUPPORT.md` for details.

## License

TransformationSwiftUI is available under the MIT license. See the LICENSE file for details.
