<div align="center">

<img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" />
<img src="https://img.shields.io/badge/macOS-13.0%2B-000000?style=for-the-badge&logo=apple&logoColor=white" />
<img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" />
<img src="https://img.shields.io/badge/SPM-compatible-brightgreen?style=for-the-badge&logo=swift&logoColor=white" />

<br /><br />

# TransformationSwiftUI

### Automatically migrate UIKit projects to idiomatic SwiftUI — in seconds.

*Parses Swift source, storyboards, XIBs, and Auto Layout constraints. Generates production-ready SwiftUI with `NavigationStack`, `TabView`, `NavigationLink`, sheets, and custom component wrappers. Optionally powered by Claude, GPT-4o, or a local LLM.*

[**Quick Start**](#installation) · [**How It Works**](#how-it-works) · [**AI Integration**](#ai-assisted-conversion) · [**Configuration**](#configuration) · [**Contributing**](#contributing)

</div>

---

## Why TransformationSwiftUI?

Migrating from UIKit to SwiftUI by hand is tedious, error-prone, and time-consuming. TransformationSwiftUI automates the structural work so you can focus on the logic that actually differentiates your app.

| What it handles | What you keep |
|---|---|
| View hierarchy reconstruction | Business logic |
| Auto Layout → SwiftUI modifiers | App-specific behaviour |
| Segue graph → NavigationStack / TabView | Custom design decisions |
| Custom UIView subclasses → View wrappers | Data models |
| IBActions → state-driven callbacks | Tests |

> **Zero runtime dependency.** The generated code uses only SwiftUI and Foundation — no wrapper libraries, no runtime frameworks.

---

## Features

- **Swift Source Parsing** — Uses SwiftSyntax to analyse `UIViewController` subclasses, extract `addSubview` hierarchies, and read `NSLayoutConstraint` declarations
- **Storyboard & XIB Support** — Parses `.storyboard` and `.xib` XML and runs them through the same five-phase pipeline as Swift source files
- **Custom Component Detection** — Discovers every `UIView` / `UIControl` subclass with full multi-pass transitive inheritance resolution; generates a standalone SwiftUI wrapper for each one
- **Navigation Flow Generation** — Extracts the complete segue graph and emits a single `AppFlowView.swift` that reconstructs every push, modal, tab, embed, and unwind relationship in native SwiftUI
- **Layout Pattern Engine** — Infers `VStack`, `HStack`, and `ZStack` arrangements from constraint graphs without any hints from you
- **Property-Aware Rendering** — Reads label text, button titles, image names, placeholder strings, and stack-view axis values directly from Interface Builder; they appear verbatim in the output
- **AI-Assisted Conversion** — Optionally routes complex screens to Claude, GPT-4o, Perplexity, or a locally-hosted model (Ollama / any OpenAI-compatible endpoint) for higher-quality results
- **RAG Indexing** — For large codebases, indexes already-converted SwiftUI files and retrieves the most relevant snippets as context for the AI layer
- **Business Logic Annotations** — Detects `IBAction` bindings, target-action patterns, programmatic navigation calls, and visibility mutations; documents them as comments in the output so nothing is silently discarded
- **Animation Detection** — Identifies `UIView.animate`, `CABasicAnimation`, `CASpringAnimation`, and `UIViewPropertyAnimator` usage; generates `.withAnimation` blocks and `@State` transitions
- **Deduplication** — When a controller exists in both a `.storyboard` and a `.swift` file, the Swift-parsed version always wins

---

## Demo

**Input — UIKit view controller (Swift + storyboard)**

```swift
class LoginViewController: UIViewController {
    @IBOutlet weak var emailField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var loginButton: UIButton!

    @IBAction func loginTapped(_ sender: UIButton) {
        // navigate to dashboard
        performSegue(withIdentifier: "showDashboard", sender: nil)
    }
}
```

**Output — Generated SwiftUI**

```swift
import SwiftUI

struct LoginViewControllerView: View {
    @State private var emailFieldText: String = ""
    @State private var passwordFieldText: String = ""
    @State private var isShowingDashboard: Bool = false

    var body: some View {
        VStack {
            TextField("Email", text: $emailFieldText)
            SecureField("Password", text: $passwordFieldText)
            Button("Sign In") {
                // TODO: Business logic — loginTapped IBAction
                isShowingDashboard = true
            }
        }
        .navigationDestination(isPresented: $isShowingDashboard) {
            DashboardViewControllerView()
        }
    }
}

#Preview {
    LoginViewControllerView()
}
```

**Output — `AppFlowView.swift` (top-level entry point)**

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

---

## Requirements

| | Minimum |
|---|---|
| macOS | 13.0 |
| Swift | 5.9 |
| Xcode | 15.0 (development only) |

---

## Installation

### Command-line tool

```bash
git clone https://github.com/kanchanproseth/TransformationSwiftUI.git
cd TransformationSwiftUI
swift build -c release
```

The binary is placed at `.build/release/TransformationSwiftUICLI`. Copy it anywhere on your `PATH`:

```bash
cp .build/release/TransformationSwiftUICLI /usr/local/bin/TransformationSwiftUICLI
```

### Library via Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
.package(url: "https://github.com/kanchanproseth/TransformationSwiftUI.git", from: "1.0.0")
```

Then import and call the runner:

```swift
import TransformationSwiftUI

let exitCode = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/your/UIKitProject"
)
```

**Xcode integration:**
1. `File` → `Add Package Dependencies…`
2. Paste the repository URL
3. Select the `TransformationSwiftUI` product and add it to your target
4. Import and call the runner (see above)

---

## Usage

### Basic conversion

Point the tool at any UIKit project root:

```bash
TransformationSwiftUICLI /path/to/your/UIKitProject
```

Generated files land in `<project-path>/SwiftUIMigrated/`:

| Input | Output |
|---|---|
| `LoginViewController.swift` | `LoginViewControllerView.swift` |
| `RoundedButton.swift` (custom `UIButton`) | `RoundedButtonView.swift` |
| `Main.storyboard` (ProfileViewController scene) | `ProfileViewControllerView.swift` |
| `CardView.xib` | `CardViewView.swift` |
| `Main.storyboard` (segue graph) | `AppFlowView.swift` |

Or run directly via SwiftPM without installing:

```bash
swift run TransformationSwiftUICLI /path/to/your/UIKitProject
```

### Generate an Xcode project scaffold

```bash
TransformationSwiftUICLI /path/to/your/UIKitProject \
  --create-project \
  --app-name MySwiftUIApp
```

### Library usage with full configuration

```swift
import TransformationSwiftUI

let exitCode = TransformationSwiftUIRunner.run(
    projectPath: "/Users/me/Projects/LegacyUIKitApp",
    createProject: true,
    appName: "MyApp",
    aiConfig: AIConversionConfig(
        enabled: true,
        minimumComplexity: 12,
        forceAI: false
    )
)
```

---

## How It Works

The pipeline runs in five sequential phases:

```
Phase 1 — Custom Component Discovery
  FileScanner discovers all .swift files.
  CustomComponentAnalyzer performs multi-pass inheritance resolution.
  CustomComponentRegistry is built: every UIView/UIControl subclass mapped.

Phase 2 — Custom Component Code Generation
  A SwiftUI View struct is emitted for each discovered component.

Phase 3 — Swift Source Parsing
  SwiftParser visits each .swift file with a suite of syntax visitors:
    ViewControllerVisitor    → UIViewController subclasses
    ViewHierarchyVisitor     → addSubview / addArrangedSubview trees
    AutoLayoutVisitor        → NSLayoutConstraint declarations
    AnimationVisitor         → UIView.animate / CA* usage
    VisibilityLogicVisitor   → isHidden / alpha mutations
    BusinessLogicVisitor     → IBActions and programmatic navigation
    LayoutPatternEngine      → VStack / HStack / ZStack inference
  SwiftUICodeGenerator produces the final output (rule-based or AI-routed).

Phase 4 — Interface Builder Parsing
  FileScanner finds all .storyboard and .xib files.
  StoryboardParser reads XML via IBElementMapper, IBConstraintMapper,
  and IBSegueMapper.
  Same SwiftUICodeGenerator pipeline; Phase 3 controllers are skipped.

Phase 5 — Navigation Flow Generation
  StoryboardParser.parseNavigationGraph extracts the segue graph.
  Graphs from multiple storyboards are merged (deduplicated by src+dst+kind).
  Programmatic navigation from Phase 3 is integrated.
  NavigationFlowGenerator emits AppFlowView.swift — the SwiftUI entry point.
```

### Complexity scoring

Before invoking the AI layer, each view controller is assigned a complexity score:

```
score = nodeCount
      + constraintCount
      + (unknownNodeCount   × 3)   // custom types not in registry
      + (unsupportedCount   × 2)   // unsupported UIKit types
      + (treeDepth          × 2)
```

Screens below the threshold are converted with the rule-based engine (fast, deterministic). Screens above it are sent to the AI layer for higher-quality output.

---

## Navigation: Supported segue types

| UIKit | SwiftUI |
|---|---|
| `show` / `push` | `NavigationLink` inside `NavigationStack` |
| `presentation` / `modal` | `.sheet` |
| `presentation` (fullScreen) | `.fullScreenCover` |
| `relationship` on `UITabBarController` | `TabView` with labelled tabs |
| `embed` | Inline child view |
| `unwind` | `@Environment(\.dismiss)` |

---

## AI-Assisted Conversion

Enable AI conversion by setting `TRANSFORMATION_SWIFTUI_AI_ENABLED=1` and supplying one API key. Cloud providers take priority over a local endpoint when both are set.

### Anthropic (Claude) — default: `claude-sonnet-4-20250514`

```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY=sk-ant-api03-...
# Optional:
# export TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL=claude-opus-4-20250514
TransformationSwiftUICLI /path/to/your/UIKitProject
```

### OpenAI — default: `gpt-4o`

```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_OPENAI_API_KEY=sk-...
# Optional:
# export TRANSFORMATION_SWIFTUI_OPENAI_MODEL=gpt-4o
TransformationSwiftUICLI /path/to/your/UIKitProject
```

### Perplexity — default: `sonar`

```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY=pplx-...
TransformationSwiftUICLI /path/to/your/UIKitProject
```

### Local / Ollama — default: `deepseek-r1:1.5b`

```bash
export TRANSFORMATION_SWIFTUI_AI_ENABLED=1
export TRANSFORMATION_SWIFTUI_AI_ENDPOINT=http://localhost:11434/api/generate
# Optional:
# export TRANSFORMATION_SWIFTUI_AI_MODEL=deepseek-r1:1.5b
TransformationSwiftUICLI /path/to/your/UIKitProject
```

### Test AI connectivity without converting a project

```bash
# Print response to stdout
TransformationSwiftUICLI --ai-smoke-test "Convert a UIButton to SwiftUI."

# Write response to a file
TransformationSwiftUICLI --ai-smoke-test "Convert a UIButton to SwiftUI." \
  --ai-smoke-output /tmp/ai-output.swift
```

---

## RAG Indexing

For large projects, enable retrieval-augmented generation to supply relevant already-converted SwiftUI code as context to the AI layer:

```bash
export TRANSFORMATION_SWIFTUI_RAG_ENABLED=1
TransformationSwiftUICLI /path/to/your/UIKitProject
```

---

## Configuration

All configuration is done through environment variables — no config files, no flags.

### AI conversion

| Variable | Default | Description |
|---|---|---|
| `TRANSFORMATION_SWIFTUI_AI_ENABLED` | `0` | Set to `1` to enable AI-assisted conversion |
| `TRANSFORMATION_SWIFTUI_AI_MIN_COMPLEXITY` | `12` | Complexity score threshold for routing to AI |
| `TRANSFORMATION_SWIFTUI_AI_FORCE` | `0` | Set to `1` to always use AI regardless of score |
| `TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY` | — | Anthropic API key |
| `TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | Override Anthropic model |
| `TRANSFORMATION_SWIFTUI_ANTHROPIC_ENDPOINT` | — | Override Anthropic endpoint |
| `TRANSFORMATION_SWIFTUI_OPENAI_API_KEY` | — | OpenAI API key |
| `TRANSFORMATION_SWIFTUI_OPENAI_MODEL` | `gpt-4o` | Override OpenAI model |
| `TRANSFORMATION_SWIFTUI_OPENAI_ENDPOINT` | — | Override OpenAI endpoint |
| `TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY` | — | Perplexity API key |
| `TRANSFORMATION_SWIFTUI_PERPLEXITY_MODEL` | `sonar` | Override Perplexity model |
| `TRANSFORMATION_SWIFTUI_PERPLEXITY_ENDPOINT` | — | Override Perplexity endpoint |
| `TRANSFORMATION_SWIFTUI_AI_ENDPOINT` | — | URL for local / Ollama endpoint |
| `TRANSFORMATION_SWIFTUI_AI_MODEL` | `deepseek-r1:1.5b` | Override local model name |

### RAG indexing

| Variable | Default | Description |
|---|---|---|
| `TRANSFORMATION_SWIFTUI_RAG_ENABLED` | `0` | Set to `1` to enable RAG context |
| `TRANSFORMATION_SWIFTUI_RAG_TOP_K` | `4` | Number of retrieved chunks per query |
| `TRANSFORMATION_SWIFTUI_RAG_CHUNK_SIZE` | `1200` | Characters per code chunk |
| `TRANSFORMATION_SWIFTUI_RAG_CHUNK_OVERLAP` | `200` | Overlap characters between adjacent chunks |

---

## Project Structure

```
TransformationSwiftUI/
├── Package.swift
├── Sources/
│   ├── TransformationSwiftUI/              # Library target
│   │   ├── TransformationSwiftUIRunner.swift     # Public entry point
│   │   ├── SwiftUICodeGenerator.swift           # Rule-based code generation
│   │   ├── SwiftUIRenderers.swift               # Per-element rendering
│   │   ├── CustomComponentRenderer.swift        # UIView subclass → SwiftUI wrapper
│   │   ├── NavigationFlowGenerator.swift        # AppFlowView.swift generation
│   │   ├── AnimationRenderer.swift              # Animation state + modifiers
│   │   ├── DrawingRenderer.swift                # Core Graphics translation
│   │   ├── AIConversionLayer.swift              # Complexity scoring + AI routing
│   │   ├── AIPromptBuilder.swift                # Prompt construction
│   │   ├── CloudAIConversionProvider.swift      # Cloud LLM HTTP client
│   │   ├── LocalAIConversionProvider.swift      # Local LLM HTTP client
│   │   ├── RAGIndex.swift                       # Retrieval-augmented generation
│   │   ├── ProjectScaffoldGenerator.swift       # Xcode project scaffold
│   │   ├── Analyzer/
│   │   │   ├── ViewControllerVisitor.swift      # UIViewController discovery
│   │   │   ├── ViewHierarchyVisitor.swift       # addSubview tree builder
│   │   │   ├── AutoLayoutVisitor.swift          # NSLayoutConstraint extractor
│   │   │   ├── LayoutPatternEngine.swift        # VStack/HStack/ZStack inference
│   │   │   ├── UIKitComponentVisitor.swift      # UIKit element declarations
│   │   │   ├── CustomComponentVisitor.swift     # UIView/UIControl subclass discovery
│   │   │   ├── CustomComponentAnalyzer.swift    # Multi-pass inheritance resolution
│   │   │   ├── PropertyExtractorVisitor.swift   # Exposed property extraction
│   │   │   ├── AnimationVisitor.swift           # Animation usage detection
│   │   │   ├── VisibilityLogicVisitor.swift     # isHidden/alpha tracking
│   │   │   ├── BusinessLogicVisitor.swift       # IBActions + navigation calls
│   │   │   └── DrawingCommandVisitor.swift      # Core Graphics command detection
│   │   ├── Models/
│   │   │   ├── UIElementNode.swift              # View tree node
│   │   │   ├── UIKitElementType.swift           # Supported UIKit component enum
│   │   │   ├── LayoutConstraint.swift           # Auto Layout constraint model
│   │   │   ├── ViewControllerModel.swift        # Root model: hierarchy + navigation
│   │   │   ├── NavigationGraph.swift            # Segue graph model
│   │   │   ├── CustomComponentModel.swift       # Custom component + inheritance chain
│   │   │   ├── CustomComponentRegistry.swift    # Type resolution registry
│   │   │   ├── AnimationModel.swift             # Animation descriptor
│   │   │   └── DrawingModel.swift               # Drawing command descriptor
│   │   └── Parser/
│   │       ├── SwiftParser.swift                # Swift source orchestrator
│   │       ├── StoryboardParser.swift           # Storyboard / XIB XML parser
│   │       ├── IBElementMapper.swift            # IB XML → UIKitElementType
│   │       ├── IBConstraintMapper.swift         # IB constraints → LayoutConstraint
│   │       └── IBSegueMapper.swift              # IB segue kind → SegueKind
│   └── TransformationSwiftUICLI/           # CLI target
│       └── main.swift                           # Entry point; delegates to runner
└── Tests/
    └── TransformationSwiftUITests/
        └── UIKitElementTypeTests.swift
```

---

## Dependencies

| Package | Purpose |
|---|---|
| [apple/swift-syntax](https://github.com/apple/swift-syntax) | Swift AST parsing (SwiftSyntax + SwiftParser products) |

No other external dependencies. Storyboard and XIB parsing uses Foundation's built-in `XMLDocument`.

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

Some good starting points:

- Add support for additional UIKit element types in `UIKitElementType.swift`
- Improve layout inference in `LayoutPatternEngine.swift`
- Add more AI prompt strategies in `AIPromptBuilder.swift`
- Expand the test suite in `TransformationSwiftUITests/`

---

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please read it before participating.

## Security

If you discover a security issue, please report it responsibly. See [SECURITY.md](SECURITY.md) for details.

## Support

For questions, use [Discussions](https://github.com/kanchanproseth/TransformationSwiftUI/discussions). For bugs and feature requests, [open an issue](https://github.com/kanchanproseth/TransformationSwiftUI/issues).

See [SUPPORT.md](SUPPORT.md) for details.

## License

TransformationSwiftUI is released under the MIT License. See [LICENSE](LICENSE) for details.
