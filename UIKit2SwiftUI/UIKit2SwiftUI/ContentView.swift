//
//  ContentView.swift
//  UIKit2SwiftUI
//
//  Created by Kan Chanproseth on 3/24/26.
//

import SwiftUI
import TransformationSwiftUI

// MARK: - View model

@MainActor
@Observable
final class ConversionViewModel {
    var projectPath: String = ""
    var isRunning: Bool = false
    var totalItems: Int = 0
    var completedItems: Int = 0
    var currentItem: String = ""
    var logLines: [String] = []
    var writtenFiles: [String] = []
    var outputDirectory: String = ""
    var errorMessage: String?

    var fraction: Double {
        totalItems > 0 ? Double(completedItems) / Double(totalItems) : 0
    }
    var percent: Int {
        totalItems > 0 ? (completedItems * 100) / totalItems : 0
    }
    var isDone: Bool { !isRunning && !outputDirectory.isEmpty }
    var hasError: Bool { errorMessage != nil }

    func start() {
        guard !projectPath.isEmpty, !isRunning else { return }
        reset()
        isRunning = true

        let session = ConversionSession(projectPath: projectPath)

        Task {
            for await event in session.start() {
                switch event {
                case .prepared(let total):
                    totalItems = total
                case .progress(let p):
                    completedItems = p.completed
                    currentItem = p.currentItem
                    logLines.append("[\(p.percent)%] \(p.currentItem)")
                case .skipped(let p):
                    completedItems = p.completed
                    logLines.append("[skip] \(p.currentItem)")
                case .log(let message):
                    logLines.append(message)
                case .fileWritten(let path, _):
                    writtenFiles.append(path)
                case .completed(let dir, let count):
                    outputDirectory = dir
                    currentItem = "Done — \(count) file(s) written"
                    isRunning = false
                case .failed(let error):
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    private func reset() {
        totalItems = 0
        completedItems = 0
        currentItem = ""
        logLines = []
        writtenFiles = []
        outputDirectory = ""
        errorMessage = nil
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var viewModel = ConversionViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: Sidebar — controls + file list

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            projectPicker
            convertButton
            if viewModel.isRunning || viewModel.isDone {
                progressSection
            }
            if !viewModel.writtenFiles.isEmpty {
                fileList
            }
            Spacer()
        }
        .padding()
        .navigationTitle("UIKit → SwiftUI")
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UIKit Project")
                .font(.headline)
            HStack {
                TextField("Select a folder…", text: $viewModel.projectPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isRunning)
                Button("Browse") {
                    pickFolder()
                }
                .disabled(viewModel.isRunning)
            }
        }
    }

    private var convertButton: some View {
        Button {
            viewModel.start()
        } label: {
            Label("Convert", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.projectPath.isEmpty || viewModel.isRunning)
        .controlSize(.large)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(viewModel.currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(viewModel.percent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.fraction)
                .progressViewStyle(.linear)
            if viewModel.isDone {
                Label("Output: \(viewModel.outputDirectory)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: viewModel.outputDirectory))
                }
                .font(.caption)
            }
            if viewModel.hasError, let msg = viewModel.errorMessage {
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Written files (\(viewModel.writtenFiles.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(viewModel.writtenFiles, id: \.self) { path in
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }
            .listStyle(.sidebar)
            .frame(maxHeight: 200)
        }
    }

    // MARK: Detail — log

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log")
                .font(.headline)
                .padding([.horizontal, .top])
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(logColor(for: line))
                                .padding(.horizontal)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.logLines.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Helpers

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.projectPath = url.path
        }
    }

    private func logColor(for line: String) -> Color {
        if line.hasPrefix("[skip]") { return .secondary }
        if line.hasPrefix("Failed") || line.hasPrefix("Error") { return .red }
        if line.hasPrefix("SwiftUI →") || line.hasPrefix("SwiftUI (IB)") { return .green }
        if line.contains("%]") { return .primary }
        return .secondary
    }
}

#Preview {
    ContentView()
}
