# TransformationSwiftUI — Claude Skill

## What this library does

`TransformationSwiftUI` is a Swift Package Manager library + CLI that **automatically converts UIKit projects to idiomatic SwiftUI**. It parses Swift source files, `.storyboard` files, and `.xib` files, then generates production-ready SwiftUI code including `NavigationStack`, `TabView`, `NavigationLink`, `.sheet`, and custom component wrappers.

It is available at: https://github.com/kanchanproseth/TransformationSwiftUI

---

## Adding to a project

```swift
// Package.swift
.package(url: "https://github.com/kanchanproseth/TransformationSwiftUI.git", from: "0.0.1")

// In a target:
.product(name: "TransformationSwiftUI", package: "TransformationSwiftUI")
```

---

## The simplest usage

```swift
import TransformationSwiftUI

// Convert a UIKit project directory
let exitCode = TransformationSwiftUIRunner.run(
    projectPath: "/Users/me/MyLegacyApp"
)
// Generated files appear in /Users/me/MyLegacyApp/SwiftUIMigrated/
```

---

## Core API patterns

### 1. Run the full pipeline

```swift
import TransformationSwiftUI

// Minimal — rule-based only, no AI
let code = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/UIKitProject"
)

// With AI (Anthropic auto-detected from env)
let code = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/UIKitProject",
    aiConfig: AIConversionConfig(enabled: true, minimumComplexity: 12, forceAI: false)
)

// With an explicit AI provider
let provider = CloudAIConversionProvider(
    format: .anthropic,
    endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
    apiKey: "sk-ant-...",
    model: "claude-sonnet-4-20250514"
)
let code = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/UIKitProject",
    aiProvider: provider,
    aiConfig: AIConversionConfig(enabled: true, minimumComplexity: 8, forceAI: false)
)

// With project scaffold generation
let code = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/UIKitProject",
    createProject: true,
    appName: "MyApp"
)
```

### 2. Parse a single Swift file

```swift
import TransformationSwiftUI

let models = try SwiftParser.parseFile(URL(fileURLWithPath: "/path/to/LoginViewController.swift"))
// models: [ViewControllerModel]
for model in models {
    let swiftUI = SwiftUICodeGenerator.generate(for: model, aiProvider: nil)
    print(swiftUI)
}
```

### 3. Parse a storyboard

```swift
import TransformationSwiftUI

let models = StoryboardParser.parseFile(URL(fileURLWithPath: "/path/to/Main.storyboard"))
for model in models {
    let swiftUI = SwiftUICodeGenerator.generate(for: model, aiProvider: nil)
    print(swiftUI)
}
```

### 4. Generate code from a model you built manually

```swift
import TransformationSwiftUI

// Build a model by hand
var model = ViewControllerModel(name: "LoginViewController")
model.rootElements = [
    UIElementNode(name: "emailField", type: .textField),
    UIElementNode(name: "loginButton", type: .button),
]
model.constraints = [
    LayoutConstraint(
        firstItem: "emailField", firstAttribute: .width,
        relation: .equal, secondItem: nil, secondAttribute: nil,
        constant: 300
    )
]

// Generate SwiftUI
let output = SwiftUICodeGenerator.generate(for: model, aiProvider: nil)
print(output)
// → struct LoginViewControllerView: View { ... }
```

### 5. Use a custom AI provider

```swift
import TransformationSwiftUI
import Foundation

struct MyAIProvider: AIConversionProvider {
    func convert(_ request: AIConversionRequest) throws -> String? {
        // request.controller  — the ViewControllerModel
        // request.patterns    — inferred LayoutPatterns
        // request.layoutHints — modifier hints
        // request.contextChunks — RAG context
        let prompt = AIPromptBuilder.buildUserPrompt(from: request)
        // call your own API with prompt ...
        return nil // or return generated SwiftUI source
    }
}

let code = TransformationSwiftUIRunner.run(
    projectPath: "/path/to/project",
    aiProvider: MyAIProvider(),
    aiConfig: AIConversionConfig(enabled: true, minimumComplexity: 0, forceAI: true)
)
```

### 6. Build and query a RAG index

```swift
import TransformationSwiftUI

let config = RAGConfig(enabled: true, topK: 4, chunkSize: 1200, chunkOverlap: 200)
let index = RAGIndex(config: config)

// Index all Swift files in a directory
let files = FileScanner.findSwiftFiles(at: "/path/to/SwiftUIMigrated")
let chunkCount = index.indexFiles(files)

// Retrieve relevant chunks for a controller
let model: ViewControllerModel = ...
let query = RAGQueryBuilder.build(for: model)
let chunks = index.retrieve(query: query, topK: 4)
// Pass chunks into the AI request via AIConversionRequest.contextChunks
```

### 7. Generate navigation flow from a graph

```swift
import TransformationSwiftUI

// Obtain a graph from parsing
let graph = StoryboardParser.parseNavigationGraph(
    from: [URL(fileURLWithPath: "/path/to/Main.storyboard")]
)

let allNames: Set<String> = ["LoginViewControllerView", "DashboardViewControllerView"]
let appFlowSource = NavigationFlowGenerator.generateAppFlowView(
    graph: graph, allVCNames: allNames
)
// Write appFlowSource to AppFlowView.swift

// Per-VC navigation injection
let injection = NavigationFlowGenerator.navigationInjection(
    for: "LoginViewControllerView", graph: graph, allVCNames: allNames
)
// injection.stateLines   — @State declarations to add
// injection.modifierLines — .sheet / .fullScreenCover modifiers
// injection.linkLines    — NavigationLink lines
```

### 8. Work with the custom component registry

```swift
import TransformationSwiftUI

let registry = CustomComponentRegistry()

// Register a discovered component
let component = CustomComponentModel(
    name: "RoundedButton",
    superclassName: "UIButton",
    resolvedBaseType: .button,
    inheritanceChain: ["RoundedButton", "UIButton"],
    sourceFilePath: "/path/to/RoundedButton.swift",
    internalElements: [],
    internalConstraints: [],
    exposedProperties: [],
    syntaxNode: ..., // ClassDeclSyntax from swift-syntax
    drawingModel: nil,
    animations: []
)
registry.register(component)

// Resolve a type name encountered during parsing
switch registry.resolveType("RoundedButton") {
case .builtIn(let type):  print("built-in:", type)
case .custom(let model):  print("custom:", model.name)
case .unknown:            print("unknown type")
}
```

### 9. Score complexity before deciding to use AI

```swift
import TransformationSwiftUI

let model: ViewControllerModel = ...
let score = AIConversionScorer.score(controller: model)
// score = nodeCount + constraintCount + (unknownCount×3) + (unsupportedCount×2) + (treeDepth×2)

if score >= 12 {
    // route to AI
}
```

### 10. Infer layout patterns from constraints

```swift
import TransformationSwiftUI

let constraints: [LayoutConstraint] = ...
let patterns = LayoutPatternEngine.inferPatterns(from: constraints)
// → [LayoutPattern(type: .vStack, elements: ["titleLabel", "subtitleLabel"]),
//    LayoutPattern(type: .hStack, elements: ["avatarImage", "titleLabel"])]

let hints = LayoutPatternEngine.inferHints(from: constraints)
// → ["avatar.frame(width: 44)", "avatar.padding(.leading, 12)"]
```

---

## Key types cheatsheet

| Type | Role |
|---|---|
| `TransformationSwiftUIRunner` | Main entry point — runs the full pipeline |
| `ViewControllerModel` | Data model for one converted screen |
| `UIElementNode` | One node in the view hierarchy tree |
| `UIKitElementType` | Enum of all supported UIKit component types |
| `LayoutConstraint` | Auto Layout constraint (normalized) |
| `NavigationGraph` | Full segue graph from storyboards |
| `SegueEdge` | A directed navigation edge (push/sheet/tab/…) |
| `CustomComponentModel` | A project-defined UIView/UIControl subclass |
| `CustomComponentRegistry` | Resolves type names to built-in or custom types |
| `AIConversionConfig` | AI feature flags and complexity threshold |
| `AIConversionProvider` | Protocol — implement to add a custom AI backend |
| `CloudAIConversionProvider` | Built-in provider for Anthropic/OpenAI/Perplexity |
| `LocalAIConversionProvider` | Built-in provider for Ollama / local endpoints |
| `RAGIndex` | Chunk, embed, store, and retrieve source files |
| `RAGConfig` | RAG feature flags and tuning params |
| `SwiftUICodeGenerator` | Generates SwiftUI source from a `ViewControllerModel` |
| `NavigationFlowGenerator` | Generates `AppFlowView.swift` from a `NavigationGraph` |
| `LayoutPatternEngine` | Infers VStack/HStack/ZStack from constraints |
| `FileScanner` | Discovers `.swift`, `.storyboard`, `.xib` files |
| `SwiftParser` | Parses Swift source files into `ViewControllerModel` |
| `StoryboardParser` | Parses IB files into `ViewControllerModel` |

---

## Environment variables

All configuration can be set via environment variables — no code changes needed.

```bash
# AI
TRANSFORMATION_SWIFTUI_AI_ENABLED=1
TRANSFORMATION_SWIFTUI_AI_MIN_COMPLEXITY=12
TRANSFORMATION_SWIFTUI_AI_FORCE=0

# Anthropic
TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY=sk-ant-...
TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL=claude-sonnet-4-20250514  # optional

# OpenAI
TRANSFORMATION_SWIFTUI_OPENAI_API_KEY=sk-...
TRANSFORMATION_SWIFTUI_OPENAI_MODEL=gpt-4o  # optional

# Perplexity
TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY=pplx-...

# Local (Ollama)
TRANSFORMATION_SWIFTUI_AI_ENDPOINT=http://localhost:11434/api/generate
TRANSFORMATION_SWIFTUI_AI_MODEL=deepseek-r1:1.5b

# RAG
TRANSFORMATION_SWIFTUI_RAG_ENABLED=1
TRANSFORMATION_SWIFTUI_RAG_TOP_K=4
TRANSFORMATION_SWIFTUI_RAG_CHUNK_SIZE=1200
TRANSFORMATION_SWIFTUI_RAG_CHUNK_OVERLAP=200
```

---

## Output structure

All generated files are written to `<projectPath>/SwiftUIMigrated/`:

```
SwiftUIMigrated/
├── AppFlowView.swift          ← top-level navigation entry point
├── LoginViewControllerView.swift
├── DashboardViewControllerView.swift
├── RoundedButtonView.swift    ← custom UIView/UIControl wrapper
└── ...
```

---

## Full API reference

See `docs/API.md` in the repository for the complete API reference including all method signatures, property tables, and enum cases.

---

## Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode 15.0+ (for development only)
- Dependencies: [apple/swift-syntax](https://github.com/apple/swift-syntax) v509.0.0+
