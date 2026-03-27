# TransformationSwiftUI — API Reference

Complete reference for every public type, function, and property in the `TransformationSwiftUI` library.

---

## Table of Contents

- [Entry Point](#entry-point)
  - [TransformationSwiftUIRunner](#transformationswiftuirunner)
- [Streaming Library API](#streaming-library-api)
  - [ConversionSession](#conversionsession)
  - [ConversionProgress](#conversionprogress)
  - [ConversionEvent](#conversionevent)
  - [ConversionError](#conversionerror)
- [Code Generation](#code-generation)
  - [SwiftUICodeGenerator](#swiftuicodegenerator)
  - [SwiftUIRenderStrategy](#swiftuirenderstrategy)
  - [Renderers](#renderers)
  - [NavigationFlowGenerator](#navigationflowgenerator)
  - [CustomComponentDefinitionGenerator](#customcomponentdefinitiongenerator)
  - [AnimationRenderer](#animationrenderer)
  - [DrawingRenderer](#drawingrenderer)
  - [ProjectScaffoldGenerator](#projectscaffoldgenerator)
- [AI Layer](#ai-layer)
  - [AIConversionConfig](#aiconversionconfig)
  - [AIConversionProvider](#aiconversionprovider)
  - [AIConversionRequest](#aiconversionrequest)
  - [AIConversionScorer](#aiconversionscorer)
  - [AIConversionRouter](#aiconversionrouter)
  - [AIPromptBuilder](#aipromptbuilder)
  - [CloudAIConversionProvider](#cloudaiconversionprovider)
  - [LocalAIConversionProvider](#localaiconversionprovider)
- [RAG Indexing](#rag-indexing)
  - [RAGConfig](#ragconfig)
  - [RAGIndex](#ragindex)
  - [CodeChunk](#codechunk)
  - [RAGQueryBuilder](#ragquerybuilder)
  - [EmbeddingProvider / HashingEmbeddingProvider](#embeddingprovider--hashingembeddingprovider)
  - [VectorStore / InMemoryVectorStore](#vectorstore--inmemoryvectorstore)
  - [CodeChunker](#codechunker)
- [Models](#models)
  - [ViewControllerModel](#viewcontrollermodel)
  - [UIElementNode](#uielementnode)
  - [UIKitElementType](#uikitelementtype)
  - [LayoutConstraint](#layoutconstraint)
  - [NavigationGraph](#navigationgraph)
  - [SegueEdge](#segueedge)
  - [CustomComponentModel](#customcomponentmodel)
  - [CustomComponentRegistry](#customcomponentregistry)
  - [AnimationModel](#animationmodel)
  - [DrawingModel](#drawingmodel)
  - [LayoutPattern / LayoutPatternEngine](#layoutpattern--layoutpatternengine)
- [Parsers & Scanners](#parsers--scanners)
  - [FileScanner](#filescanner)
  - [SwiftParser](#swiftparser)
  - [StoryboardParser](#storyboardparser)
  - [IBElementMapper](#ibelementmapper)
  - [IBConstraintMapper](#ibconstraintmapper)
  - [IBSegueMapper](#ibseguemapper)

---

## Entry Point

### TransformationSwiftUIRunner

```swift
public struct TransformationSwiftUIRunner
```

The single public facade for running the entire UIKit → SwiftUI conversion pipeline. All five phases (custom component discovery, component code generation, Swift source parsing, Interface Builder parsing, navigation flow generation) are orchestrated through this type.

#### Methods

```swift
public static func run(
    projectPath: String,
    createProject: Bool = false,
    appName: String? = nil,
    aiProvider: AIConversionProvider? = nil,
    aiConfig: AIConversionConfig = AIConversionConfig.fromEnvironment(),
    ragConfig: RAGConfig = RAGConfig.fromEnvironment(),
    output: (String) -> Void = { print($0) }
) -> Int
```

Runs the converter for a project directory.

| Parameter | Description |
|---|---|
| `projectPath` | Absolute path to the root of the UIKit project to convert |
| `createProject` | When `true`, generates a new Xcode project scaffold in addition to the view files |
| `appName` | App name used for project scaffold naming. Defaults to the last path component of `projectPath` |
| `aiProvider` | Custom `AIConversionProvider` implementation. Pass `nil` to auto-detect from environment |
| `aiConfig` | AI feature flags and complexity thresholds |
| `ragConfig` | RAG indexing configuration |
| `output` | Logging closure, defaults to `print` |

**Returns:** Process exit code — `0` on success, non-zero on failure.

---

```swift
public static func run(
    arguments: [String],
    output: (String) -> Void = { print($0) }
) -> Int
```

CLI-style entry point that processes raw argument strings.

| Argument | Description |
|---|---|
| `<project-path>` | Path to the UIKit project |
| `--create-project` | Generate an Xcode project scaffold |
| `--app-name <name>` | App name for the scaffold |
| `--ai-smoke-test "<prompt>"` | Send a test prompt to the configured AI provider and print the response |
| `--ai-smoke-output <path>` | Write the smoke-test response to a file instead of stdout |

**Example:**
```swift
let code = TransformationSwiftUIRunner.run(
    projectPath: "/Users/me/MyLegacyApp",
    createProject: true,
    appName: "MyApp"
)
```

---

## Streaming Library API

Use `ConversionSession` when embedding the library inside an iOS or macOS app. It runs the same five-phase pipeline as `TransformationSwiftUIRunner` but streams typed `ConversionEvent` values over an `AsyncStream` instead of writing log lines to a closure.

### ConversionSession

```swift
public struct ConversionSession: Sendable
```

Runs the full UIKit → SwiftUI pipeline and yields ``ConversionEvent`` values.

#### Initializer

```swift
public init(
    projectPath: String,
    createProject: Bool = false,
    appName: String? = nil,
    aiProvider: (any AIConversionProvider & Sendable)? = nil,
    aiConfig: AIConversionConfig = .fromEnvironment(),
    ragConfig: RAGConfig = .fromEnvironment()
)
```

| Parameter | Description |
|---|---|
| `projectPath` | Absolute path to the UIKit project root |
| `createProject` | When `true`, also generates an Xcode project scaffold |
| `appName` | App name for the scaffold; defaults to the folder name |
| `aiProvider` | Custom AI provider; pass `nil` to use environment-variable detection |
| `aiConfig` | AI feature flags and thresholds |
| `ragConfig` | RAG indexing configuration |

#### Methods

```swift
public func start() -> AsyncStream<ConversionEvent>
```

Returns a finite `AsyncStream`. Work runs on a detached background task; the stream ends with `.completed` or `.failed`.

**Usage:**

```swift
let session = ConversionSession(projectPath: "/path/to/UIKitProject")

for await event in session.start() {
    switch event {
    case .prepared(let total):
        print("Total items: \(total)")
    case .progress(let p):
        progressBar.value = p.fraction        // 0.0 … 1.0
        label.text = "\(p.percent)% — \(p.currentItem)"
    case .skipped(let p):
        print("Skipped: \(p.currentItem)")
    case .log(let message):
        console.append(message)
    case .fileWritten(let path, let code):
        print("Wrote → \(path)")
    case .completed(let dir, let count):
        print("Done: \(count) files in \(dir)")
    case .failed(let error):
        print("Error: \(error)")
    }
}
```

---

### ConversionProgress

```swift
public struct ConversionProgress: Sendable
```

A progress snapshot emitted with each `.progress` and `.skipped` event.

| Property | Type | Description |
|---|---|---|
| `completed` | `Int` | Items fully processed so far |
| `total` | `Int` | Total items to process |
| `fraction` | `Double` | `0.0 … 1.0` — suitable for `ProgressView(value:)` |
| `percent` | `Int` | `0 … 100` — integer percentage |
| `currentItem` | `String` | Human-readable label, e.g. `"LoginViewController.swift → LoginViewController"` |
| `sourceFile` | `String?` | Absolute path of the source file being processed |
| `outputFile` | `String?` | Absolute path of the output file (nil until written) |

---

### ConversionEvent

```swift
public enum ConversionEvent: Sendable
```

All events emitted by `ConversionSession.start()`.

| Case | Payload | When emitted |
|---|---|---|
| `.prepared(totalItems:)` | `Int` | Once, after scanning, before any conversion begins |
| `.progress(ConversionProgress)` | `ConversionProgress` | When each item starts converting |
| `.skipped(ConversionProgress)` | `ConversionProgress` | When an IB controller is shadowed by a Swift source version |
| `.log(String)` | `String` | Diagnostic messages (mirrors CLI output) |
| `.fileWritten(outputPath:swiftUICode:)` | `String, String` | After each file is successfully written to disk |
| `.completed(outputDirectory:totalWritten:)` | `String, Int` | When the entire session finishes |
| `.failed(Error)` | `Error` | When a non-recoverable error stops the session |

---

### ConversionError

```swift
public enum ConversionError: Error, Sendable
```

Errors emitted via `.failed`.

| Case | Description |
|---|---|
| `.outputDirectoryCreationFailed(String)` | Could not create the `SwiftUIMigrated` output directory; payload is the path |
| `.noSourceFilesFound(String)` | No `.swift` or IB files found at the given project path |

---

## Code Generation

### SwiftUICodeGenerator

```swift
public struct SwiftUICodeGenerator
```

Generates a complete SwiftUI view file from a `ViewControllerModel`. Supports both a deterministic rule-based path and an optional AI-assisted path for complex screens.

#### Methods

```swift
public static func generate(
    for controller: ViewControllerModel,
    aiProvider: AIConversionProvider?,
    config: AIConversionConfig = .default,
    ragIndex: RAGIndex? = nil,
    ragConfig: RAGConfig = .default,
    componentRegistry: CustomComponentRegistry? = nil
) -> String
```

Generates the full `.swift` file content for a converted view controller.

```swift
public static func buildStateDeclarations(from roots: [UIElementNode]) -> [String]
```

Returns `@State private var` declarations for all controls that need bindings (`UITextField`, `UISwitch`, `UISlider`, `UISegmentedControl`, `UIProgressView`).

```swift
public static func modifierLines(
    for name: String,
    constraints: [LayoutConstraint],
    indent: Int
) -> [String]
```

Translates Auto Layout constraints for a named element into `.frame`, `.padding`, and `.offset` modifiers.

```swift
public static func containerName(
    for nodes: [UIElementNode],
    patterns: [LayoutPattern]
) -> String
```

Returns `"ZStack"` when a `zStack` pattern exists for the nodes, otherwise `"Group"`.

```swift
public static func sanitizedIdentifier(_ raw: String) -> String
public static func formatNumber(_ value: Double) -> String
public static func indentString(_ level: Int) -> String
```

Utility functions for identifier sanitization, number formatting, and indentation.

---

### SwiftUIRenderStrategy

```swift
public protocol SwiftUIRenderStrategy: Sendable
```

Strategy interface for per-element rendering. Each UIKit element type maps to one conforming renderer.

```swift
func render(
    node: UIElementNode,
    constraints: [LayoutConstraint],
    patterns: [LayoutPattern],
    indent: Int
) -> [String]
```

Returns the SwiftUI source lines for a single node.

---

### Renderers

All renderers are `public struct` values conforming to `SwiftUIRenderStrategy`.

| Renderer | UIKit source | SwiftUI output |
|---|---|---|
| `LabelRenderer` | `UILabel` | `Text("…")` |
| `ButtonRenderer` | `UIButton` | `Button("…") { }` |
| `ImageViewRenderer` | `UIImageView` | `Image("…").resizable()` |
| `StackViewRenderer` | `UIStackView` | `VStack` / `HStack` (axis-inferred) |
| `ViewRenderer` | `UIView` | `ZStack` / container |
| `ScrollViewRenderer` | `UIScrollView` | `ScrollView { }` |
| `TextFieldRenderer` | `UITextField` | `TextField("…", text: $…)` |
| `TextViewRenderer` | `UITextView` | `TextEditor(text: $…)` |
| `ToggleRenderer` | `UISwitch` | `Toggle("…", isOn: $…)` |
| `SliderRenderer` | `UISlider` | `Slider(value: $…)` |
| `ProgressViewRenderer` | `UIProgressView` | `ProgressView(value: …)` |
| `ListRenderer` | `UITableView` / `UICollectionView` | `List` / `LazyVGrid` |
| `ActivityIndicatorRenderer` | `UIActivityIndicatorView` | `ProgressView()` |
| `SegmentedControlRenderer` | `UISegmentedControl` | `Picker` with `.pickerStyle(.segmented)` |
| `PageControlRenderer` | `UIPageControl` | `TabView` with `.tabViewStyle(.page)` |
| `VisualEffectRenderer` | `UIVisualEffectView` | `Rectangle().fill(.ultraThinMaterial)` |

---

### NavigationFlowGenerator

```swift
public struct NavigationFlowGenerator
```

Generates `AppFlowView.swift` — the top-level SwiftUI entry point that mirrors the entire UIKit navigation structure.

#### Methods

```swift
public static func generateAppFlowView(
    graph: NavigationGraph,
    allVCNames: Set<String>
) -> String
```

Returns the complete Swift source for `AppFlowView.swift`.

```swift
public static func navigationInjection(
    for vcName: String,
    graph: NavigationGraph,
    allVCNames: Set<String>
) -> (stateLines: [String], modifierLines: [String], linkLines: [String])
```

Returns the `@State` declarations, view modifiers (`.sheet`, `.fullScreenCover`), and `NavigationLink` lines to inject into a specific view controller's generated file.

---

### CustomComponentDefinitionGenerator

```swift
public struct CustomComponentDefinitionGenerator
```

Generates a standalone SwiftUI `View` struct for a discovered custom `UIView`/`UIControl` subclass.

```swift
public static func generate(for component: CustomComponentModel) -> String
```

Returns the complete `.swift` file content for the wrapper view.

---

### AnimationRenderer

```swift
public struct AnimationRenderer
```

Generates SwiftUI animation code from `[AnimationModel]`.

```swift
public static func buildAnimationStateDeclarations(
    from animations: [AnimationModel],
    existingElements: [UIElementNode]
) -> [String]
```

Returns `@State` declarations for animated properties (e.g. `@State private var titleLabelOpacity: Double = 1`).

```swift
public static func modifierLines(
    for elementName: String,
    animations: [AnimationModel],
    indent: Int
) -> [String]
```

Returns modifiers like `.opacity(titleLabelOpacity)`, `.scaleEffect(…)` for a named element.

```swift
public static func onAppearBlock(
    from animations: [AnimationModel],
    indent: Int
) -> [String]
```

Returns `.onAppear { withAnimation { … } }` blocks for appear-context animations.

```swift
public static func swiftUIAnimationExpression(
    timingCurve: AnimationTimingCurve,
    duration: Double?
) -> String
```

Returns a SwiftUI animation expression string such as `".easeInOut(duration: 0.3)"` or `".spring(response: 0.5, dampingFraction: 0.8)"`.

---

### DrawingRenderer

```swift
public struct DrawingRenderer
```

Translates a `DrawingModel` (extracted from `draw(_ rect:)` overrides) into SwiftUI drawing code.

```swift
public static func generate(for model: DrawingModel) -> String
```

Returns a complete `.swift` file with either a `Shape` conformance (simple paths) or a `Canvas`-backed `View` (complex drawings with transforms or multiple segments).

```swift
public static func mapColor(_ uiColorExpression: String) -> String
```

Maps common UIKit color expressions (e.g. `"UIColor.red"`) to SwiftUI `Color` expressions.

---

### ProjectScaffoldGenerator

```swift
public struct ProjectScaffoldGenerator
```

Generates a new, buildable SwiftUI Xcode project that wraps all converted view files.

```swift
@discardableResult
public static func generate(
    projectPath: String,
    appName: String? = nil,
    migratedDir: URL,
    graph: NavigationGraph,
    allVCNames: Set<String>,
    listNodes: [(vcName: String, node: UIElementNode)],
    output: (String) -> Void = { print($0) }
) -> URL
```

Creates the project scaffold and returns the URL to its root directory.

---

## AI Layer

### AIConversionConfig

```swift
public struct AIConversionConfig: Equatable
```

Controls when and how the AI layer is invoked.

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `false` | Master switch for AI-assisted conversion |
| `minimumComplexity` | `Int` | `12` | Complexity score threshold; AI is invoked when score ≥ this value |
| `forceAI` | `Bool` | `false` | Bypass complexity check and always use AI |

```swift
public static let `default`: AIConversionConfig
public static func fromEnvironment(_ environment: [String: String] = ...) -> AIConversionConfig
```

`fromEnvironment` reads `TRANSFORMATION_SWIFTUI_AI_ENABLED`, `TRANSFORMATION_SWIFTUI_AI_MIN_COMPLEXITY`, and `TRANSFORMATION_SWIFTUI_AI_FORCE`.

---

### AIConversionProvider

```swift
public protocol AIConversionProvider
```

Implement this protocol to integrate a custom AI backend.

```swift
func convert(_ request: AIConversionRequest) throws -> String?
```

Return a complete SwiftUI view file as a `String`, or `nil` to fall back to rule-based generation.

**Built-in implementations:**

| Type | Description |
|---|---|
| `NoOpAIConversionProvider` | Always returns `nil`; used when no AI is configured |
| `CloudAIConversionProvider` | Calls Anthropic, OpenAI, or Perplexity cloud APIs |
| `LocalAIConversionProvider` | Calls a locally-hosted HTTP endpoint (Ollama, etc.) |

---

### AIConversionRequest

```swift
public struct AIConversionRequest
```

The full context passed to an `AIConversionProvider`.

| Property | Type | Description |
|---|---|---|
| `controller` | `ViewControllerModel` | The view controller being converted |
| `patterns` | `[LayoutPattern]` | Inferred layout patterns |
| `layoutHints` | `[String]` | Modifier hints derived from constraints |
| `complexityScore` | `Int` | Heuristic complexity score |
| `promptOverride` | `String?` | Optional custom prompt string |
| `contextChunks` | `[CodeChunk]` | RAG-retrieved context chunks |

---

### AIConversionScorer

```swift
public struct AIConversionScorer
```

Computes the heuristic complexity score used to decide whether to invoke the AI layer.

```swift
public static func score(controller: ViewControllerModel) -> Int
```

**Scoring formula:**
```
score = nodeCount
      + constraintCount
      + (unknownNodeCount   × 3)
      + (unsupportedCount   × 2)
      + (treeDepth          × 2)
```

---

### AIConversionRouter

```swift
public struct AIConversionRouter
```

Wraps an `AIConversionProvider` and applies the configured scoring threshold before calling it.

```swift
public init(provider: AIConversionProvider, config: AIConversionConfig)

public func generate(
    for controller: ViewControllerModel,
    patterns: [LayoutPattern],
    hints: [String],
    contextChunks: [CodeChunk]
) -> String?
```

Returns the AI output when the complexity threshold is met and the provider returns a non-nil result; returns `nil` otherwise.

---

### AIPromptBuilder

```swift
public struct AIPromptBuilder
```

Constructs structured prompts for AI-based conversion.

```swift
public static var systemPrompt: String
```

The system-level instruction prompt telling the model to output only valid SwiftUI.

```swift
public static func buildUserPrompt(from request: AIConversionRequest) -> String
```

Builds the user-turn prompt from the request's controller model, patterns, hints, and RAG chunks. Returns `request.promptOverride` verbatim when one is set.

---

### CloudAIConversionProvider

```swift
public struct CloudAIConversionProvider: AIConversionProvider
```

Calls Anthropic (Claude), OpenAI, or Perplexity cloud APIs.

```swift
public enum CloudAPIFormat: String {
    case anthropic   // Messages API, x-api-key auth
    case openAI      // Chat Completions API, Bearer auth
    case perplexity  // OpenAI-compatible, Bearer auth
}
```

```swift
public init(
    format: CloudAPIFormat,
    endpoint: URL,
    apiKey: String,
    model: String,
    debugEnabled: Bool = false,
    session: URLSession = .shared,
    timeout: TimeInterval = 120
)
```

```swift
public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
) -> CloudAIConversionProvider?
```

Auto-detects provider from environment. Detection order: Anthropic → OpenAI → Perplexity. Returns `nil` when no API key is present.

**Environment variables:**

| Variable | Provider |
|---|---|
| `TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY` | Anthropic |
| `TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL` | Anthropic model override |
| `TRANSFORMATION_SWIFTUI_OPENAI_API_KEY` | OpenAI |
| `TRANSFORMATION_SWIFTUI_OPENAI_MODEL` | OpenAI model override |
| `TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY` | Perplexity |
| `TRANSFORMATION_SWIFTUI_PERPLEXITY_MODEL` | Perplexity model override |

**Errors:** `ProviderError.requestFailed(statusCode:)`, `.invalidResponse`, `.emptyOutput`

---

### LocalAIConversionProvider

```swift
public struct LocalAIConversionProvider: AIConversionProvider
```

Calls a locally-hosted HTTP endpoint compatible with the Ollama generate API.

```swift
public init(
    endpoint: URL,
    model: String? = nil,
    debugEnabled: Bool = false,
    session: URLSession = .shared,
    timeout: TimeInterval = 30
)

public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
) -> LocalAIConversionProvider?
```

**Environment variables:** `TRANSFORMATION_SWIFTUI_AI_ENDPOINT`, `TRANSFORMATION_SWIFTUI_AI_MODEL`

**Errors:** `ProviderError.invalidEndpoint`, `.requestFailed`, `.invalidResponse`, `.emptyOutput`

---

## RAG Indexing

### RAGConfig

```swift
public struct RAGConfig: Equatable
```

| Property | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `false` | Enables RAG indexing and retrieval |
| `topK` | `Int` | `4` | Number of chunks to retrieve per query |
| `chunkSize` | `Int` | `1200` | Max characters per chunk |
| `chunkOverlap` | `Int` | `200` | Overlap characters between adjacent chunks |

```swift
public static let `default`: RAGConfig
public static func fromEnvironment(_ environment: [String: String] = ...) -> RAGConfig
```

Reads `TRANSFORMATION_SWIFTUI_RAG_ENABLED`, `_RAG_TOP_K`, `_RAG_CHUNK_SIZE`, `_RAG_CHUNK_OVERLAP`.

---

### RAGIndex

```swift
public final class RAGIndex
```

End-to-end retrieval index. Chunks, embeds, stores, and retrieves source files.

```swift
public init(
    config: RAGConfig,
    embedder: EmbeddingProvider = HashingEmbeddingProvider(),
    store: VectorStore = InMemoryVectorStore()
)

public func indexFiles(_ files: [URL]) -> Int   // returns chunk count
public func retrieve(query: String, topK: Int) -> [CodeChunk]
```

---

### CodeChunk

```swift
public struct CodeChunk: Hashable
```

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Stable identifier (file path + line range) |
| `filePath` | `String` | Source file path |
| `startLine` | `Int` | 1-based start line |
| `endLine` | `Int` | 1-based end line |
| `text` | `String` | Raw chunk content |

---

### RAGQueryBuilder

```swift
public struct RAGQueryBuilder
```

```swift
public static func build(for controller: ViewControllerModel) -> String
```

Produces a query string from element names, types, and constraint items to drive retrieval.

---

### EmbeddingProvider / HashingEmbeddingProvider

```swift
public protocol EmbeddingProvider {
    func embed(_ text: String) -> [Double]
}

public final class HashingEmbeddingProvider: EmbeddingProvider
public init(dimensions: Int = 64)
```

Default embedder — hashes tokens into a fixed-size vector. Swap with any implementation (e.g. a real model API).

---

### VectorStore / InMemoryVectorStore

```swift
public protocol VectorStore {
    func add(chunks: [CodeChunk], embeddings: [[Double]])
    func query(vector: [Double], topK: Int) -> [(CodeChunk, Double)]
}

public final class InMemoryVectorStore: VectorStore
public init()
```

---

### CodeChunker

```swift
public final class CodeChunker
public init(chunkSize: Int, overlap: Int)
public func chunk(text: String, filePath: String) -> [CodeChunk]
```

Splits source text into overlapping `CodeChunk` entries for indexing.

---

## Models

### ViewControllerModel

```swift
public struct ViewControllerModel
```

Root data model for a single converted screen.

| Property | Type | Description |
|---|---|---|
| `name` | `String` | View controller class name or storyboard ID |
| `rootElements` | `[UIElementNode]` | Top-level view hierarchy nodes |
| `constraints` | `[LayoutConstraint]` | All Auto Layout constraints |
| `animations` | `[AnimationModel]` | Detected UIKit animations |
| `segues` | `[SegueEdge]` | Outgoing navigation edges |
| `isNavigationRoot` | `Bool` | True when embedded in a `UINavigationController` |
| `navigationTitle` | `String?` | Navigation bar title from IB |
| `tabBarItem` | `TabBarItemInfo?` | Tab bar configuration |
| `visibilityRules` | `[VisibilityRule]` | `isHidden`/`alpha`/`addSubview` mutations |
| `controlActions` | `[ControlAction]` | `IBAction` bindings and delegate callbacks |
| `navigationCalls` | `[NavigationCall]` | Programmatic `present`/`push`/`dismiss` calls |

```swift
public init(name: String, rootElements: [UIElementNode] = [], constraints: [LayoutConstraint] = [])
```

---

### UIElementNode

```swift
public struct UIElementNode
```

A node in the extracted view hierarchy tree.

| Property | Type | Description |
|---|---|---|
| `name` | `String` | Element variable name or IB outlet name |
| `type` | `UIKitElementType?` | Resolved built-in UIKit type |
| `customComponentName` | `String?` | Custom class name when type is a project-defined subclass |
| `children` | `[UIElementNode]` | Nested child elements |
| `properties` | `[String: String]` | IB/source properties (text, title, placeholder, …) |
| `visibilityRules` | `[VisibilityRule]` | Visibility mutations targeting this element |
| `controlActions` | `[ControlAction]` | Actions bound to this element |
| `cellTypeName` | `String?` | Cell model type for table/collection views |
| `hasNestedList` | `Bool` | True when this list has nested table/collection views |

```swift
public init(
    name: String,
    type: UIKitElementType? = nil,
    customComponentName: String? = nil,
    children: [UIElementNode] = [],
    properties: [String: String] = [:]
)
```

---

### UIKitElementType

```swift
public enum UIKitElementType: CaseIterable
```

All supported UIKit component types.

| Case | UIKit class |
|---|---|
| `.label` | `UILabel` |
| `.button` | `UIButton` |
| `.imageView` | `UIImageView` |
| `.image` | `UIImage` |
| `.stackView` | `UIStackView` |
| `.view` | `UIView` |
| `.scrollView` | `UIScrollView` |
| `.textField` | `UITextField` |
| `.textView` | `UITextView` |
| `.toggleSwitch` | `UISwitch` |
| `.slider` | `UISlider` |
| `.progressView` | `UIProgressView` |
| `.tableView` | `UITableView` |
| `.collectionView` | `UICollectionView` |
| `.activityIndicatorView` | `UIActivityIndicatorView` |
| `.segmentedControl` | `UISegmentedControl` |
| `.pageControl` | `UIPageControl` |
| `.visualEffectView` | `UIVisualEffectView` |
| `.viewController` | `UIViewController` |

```swift
public static func from(typeName: String?) -> UIKitElementType?
public static func isViewController(typeName: String) -> Bool
public var typeName: String
public static let supportedComponents: Set<UIKitElementType>
```

---

### LayoutConstraint

```swift
public struct LayoutConstraint
```

A normalized Auto Layout constraint.

| Property | Type | Description |
|---|---|---|
| `firstItem` | `String` | First element name |
| `firstAttribute` | `ConstraintAttribute` | Attribute on first item |
| `relation` | `ConstraintRelation` | `.equal`, `.greaterThanOrEqual`, `.lessThanOrEqual` |
| `secondItem` | `String?` | Second element name (nil for fixed-size constraints) |
| `secondAttribute` | `ConstraintAttribute?` | Attribute on second item |
| `constant` | `Double?` | Offset / size value |

**`ConstraintAttribute` cases:** `.top`, `.bottom`, `.leading`, `.trailing`, `.left`, `.right`, `.centerX`, `.centerY`, `.width`, `.height`, `.unknown`

---

### NavigationGraph

```swift
public struct NavigationGraph
```

The complete navigation structure extracted from storyboards and Swift source.

| Property | Type | Description |
|---|---|---|
| `initialViewControllerName` | `String?` | App entry point VC name |
| `edges` | `[SegueEdge]` | All navigation edges |
| `containers` | `[ContainerController]` | Navigation stacks and tab bars |

```swift
public func outgoingEdges(from vcName: String) -> [SegueEdge]
public func isNavigationRoot(_ vcName: String) -> Bool
public func tabBar(containing vcName: String) -> ContainerController?
public func merging(_ other: NavigationGraph) -> NavigationGraph
public func addingProgrammaticEdges(from calls: [NavigationCall], sourceVC: String) -> NavigationGraph
```

---

### SegueEdge

```swift
public struct SegueEdge
```

A directed navigation edge in the graph.

| Property | Type | Description |
|---|---|---|
| `identifier` | `String?` | Segue identifier (used in `performSegue`) |
| `sourceVC` | `String` | Source view controller name |
| `destinationVC` | `String` | Destination view controller name |
| `kind` | `SegueKind` | Navigation transition type |
| `tabTitle` | `String?` | Tab label (`.tab` edges only) |
| `tabImage` | `String?` | Tab SF Symbol name (`.tab` edges only) |
| `tabIndex` | `Int?` | Zero-based tab position (`.tab` edges only) |

**`SegueKind` cases:** `.push`, `.sheet`, `.fullScreenCover`, `.tab`, `.embed`, `.unwind`, `.custom`, `.programmaticPresent`, `.programmaticPush`, `.programmaticDismiss`, `.tableViewDidSelect`, `.collectionViewDidSelect`

---

### CustomComponentModel

```swift
public struct CustomComponentModel: @unchecked Sendable
```

A `UIView`/`UIControl` subclass discovered in the project.

| Property | Type | Description |
|---|---|---|
| `name` | `String` | Class name (e.g. `"RoundedButton"`) |
| `superclassName` | `String` | Immediate superclass (e.g. `"UIButton"`) |
| `resolvedBaseType` | `UIKitElementType` | Root UIKit type after traversing inheritance |
| `inheritanceChain` | `[String]` | Full chain from class to UIKit base |
| `sourceFilePath` | `String` | Source file defining the class |
| `internalElements` | `[UIElementNode]` | Subviews added inside the component |
| `internalConstraints` | `[LayoutConstraint]` | Internal constraints |
| `exposedProperties` | `[CustomComponentProperty]` | Public/internal properties |
| `drawingModel` | `DrawingModel?` | Drawing model from `draw(_ rect:)`, if present |
| `animations` | `[AnimationModel]` | Detected animations |

---

### CustomComponentRegistry

```swift
public final class CustomComponentRegistry
```

Resolves type names to built-in UIKit types or discovered custom components.

```swift
public func register(_ component: CustomComponentModel)
public func lookup(_ className: String) -> CustomComponentModel?
public func isCustomComponent(_ className: String) -> Bool
public func resolveType(_ typeName: String?) -> ResolvedComponentType
```

**`ResolvedComponentType`:**
```swift
public enum ResolvedComponentType {
    case builtIn(UIKitElementType)
    case custom(CustomComponentModel)
    case unknown
}
```

```swift
public static let uiViewHierarchyBaseClasses: Set<String>
```

All `UIView`/`UIControl` base class names used to seed discovery.

---

### AnimationModel

```swift
public struct AnimationModel
```

A single detected UIKit animation.

| Property | Type | Description |
|---|---|---|
| `kind` | `AnimationKind` | The UIKit animation API variant |
| `duration` | `Double?` | Duration in seconds |
| `delay` | `Double?` | Delay in seconds |
| `timingCurve` | `AnimationTimingCurve` | Timing curve |
| `context` | `AnimationContext` | Lifecycle context where the animation was found |
| `targetElementName` | `String?` | The view being animated |
| `propertyChanges` | `[AnimatedPropertyChange]` | Animated property mutations |
| `hasCompletion` | `Bool` | Whether a completion closure was detected |

**Key enums:**

`AnimationKind`: `.uiViewAnimate`, `.uiViewSpringAnimate`, `.uiViewTransition`, `.propertyAnimator`, `.caBasicAnimation(String)`, `.caKeyframeAnimation(String)`, `.caSpringAnimation(String)`, `.caAnimationGroup`

`AnimationTimingCurve`: `.easeInOut`, `.easeIn`, `.easeOut`, `.linear`, `.spring(dampingFraction:response:)`, `.custom`

`AnimatedPropertyChange`: `.alpha(Double)`, `.transform(AnimatedTransform)`, `.backgroundColor(String)`, `.isHidden(Bool)`, `.frame`

`AnimationContext`: `.viewDidAppear`, `.viewWillAppear`, `.viewDidLoad`, `.actionMethod(String)`, `.other(String)`

---

### DrawingModel

```swift
public struct DrawingModel
```

Extracted drawing operations from a `draw(_ rect:)` override.

| Property | Type | Description |
|---|---|---|
| `className` | `String` | The UIView subclass name |
| `segments` | `[DrawingPathSegment]` | Ordered path segments |
| `isSimpleShape` | `Bool` | True → render as SwiftUI `Shape`; false → render as `Canvas` |
| `usesContextTransforms` | `Bool` | True when `translateBy`/`scaleBy`/`rotate` were used |

```swift
public struct DrawingPathSegment
    commands: [DrawingCommand]
    fillColor: String?
    strokeColor: String?
    lineWidth: String?
```

---

### LayoutPattern / LayoutPatternEngine

```swift
public enum LayoutPatternType: CaseIterable {
    case vStack, hStack, zStack
    public var displayName: String  // "VStack", "HStack", "ZStack"
}

public struct LayoutPattern {
    public let type: LayoutPatternType
    public let elements: [String]
}

public struct LayoutPatternEngine {
    public static func inferPatterns(from constraints: [LayoutConstraint]) -> [LayoutPattern]
    public static func inferHints(from constraints: [LayoutConstraint]) -> [String]
}
```

---

## Parsers & Scanners

### FileScanner

```swift
public struct FileScanner
```

```swift
public static func findSwiftFiles(at path: String) -> [URL]
public static func findInterfaceBuilderFiles(at path: String) -> [URL]
public static func findAllSourceFiles(at path: String) -> (swift: [URL], interfaceBuilder: [URL])
```

---

### SwiftParser

```swift
public struct SwiftParser
```

```swift
public static func parseFile(_ url: URL) throws -> [ViewControllerModel]
public static func parseFile(_ url: URL, componentRegistry: CustomComponentRegistry?) throws -> [ViewControllerModel]
```

Parses a Swift source file using SwiftSyntax and returns one `ViewControllerModel` per `UIViewController` subclass found.

---

### StoryboardParser

```swift
public struct StoryboardParser
```

```swift
public static func parseFile(
    _ url: URL,
    componentRegistry: CustomComponentRegistry? = nil
) -> [ViewControllerModel]
```

Parses a `.storyboard` or `.xib` file using Foundation's `XMLDocument`. Returns one `ViewControllerModel` per scene or root view.

---

### IBElementMapper

```swift
public struct IBElementMapper
```

```swift
public static func elementType(forXMLName xmlName: String) -> UIKitElementType?
public static func extractProperties(from element: XMLElement) -> [String: String]
```

Maps IB XML tag names (e.g. `"label"`, `"button"`) to `UIKitElementType`, and extracts display properties from XML attributes.

---

### IBConstraintMapper

```swift
public struct IBConstraintMapper
```

```swift
public static func mapConstraints(
    from constraintElements: [XMLElement],
    idToName: [String: String],
    owningViewName: String?
) -> [LayoutConstraint]
```

Converts `<constraint>` XML elements into `LayoutConstraint` instances. `idToName` maps IB element IDs to resolved outlet names.

---

### IBSegueMapper

```swift
struct IBSegueMapper  // internal, used by StoryboardParser
```

```swift
static func segueKind(forKindString kindString: String, segueElement: XMLElement) -> SegueKind
static func segueKind(forKindString kindString: String) -> SegueKind
```

Maps the IB segue `kind` attribute string to a `SegueKind`, applying `modalPresentationStyle` refinement for presentation segues.

---

*Generated from TransformationSwiftUI v0.0.4.*
