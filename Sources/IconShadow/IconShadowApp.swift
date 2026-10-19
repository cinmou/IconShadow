import SwiftUI
import AppKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import IconShadowCore
#endif

@main
struct IconShadowApp: App {
    @State private var model = EditorModel()
    var body: some Scene {
        Window("Icon Shadow", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 580)
                .onOpenURL { model.load($0) }
        }
        .defaultSize(width: 1020, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", systemImage: "folder") { model.open() }.keyboardShortcut("o")
                Button("Export ICNS…") { model.export(icns: true) }
                    .keyboardShortcut("e").disabled(model.output == nil || model.busy || model.loading)
                Button("Export PNG…") { model.export(icns: false) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.output == nil || model.busy || model.loading)
            }
        }
    }
}

@MainActor @Observable
final class EditorModel {
    var source: IconSource?
    var output: CGImage?
    var filename = ""
    var settings = IconSettings()
    var preset: IconPreset = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 ? .macOS26 : .macOS27
    var busy = false
    var loading = false
    var rendering = false
    var error: String?
    var status = String(localized: "Image or App")
    private var renderTask: Task<Void, Never>?
    private var loadID = UUID()
    private var renderRevision = 0
    private var isAdjusting = false

    func applyPreset(_ value: IconPreset) {
        preset = value
        if value != .custom { settings = IconSettings() }
    }

    func reset() {
        if preset == .custom { preset = .macOS27 }
        settings = IconSettings()
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconRenderer.supportedImageTypes + NativeIconImporter.vectorTypes + [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        let id = UUID(); loadID = id
        loading = true
        Task {
            do {
                let loaded: IconSource
                if NativeIconImporter.handles(url) {
                    loaded = try NativeIconImporter.load(url)
                } else {
                    loaded = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try IconRenderer.load(url)
                    }.value
                }
                guard loadID == id else { return }
                source = loaded; filename = url.deletingPathExtension().lastPathComponent
                loading = false; output = nil
                status = "\(url.lastPathComponent) · \(loaded.width) × \(loaded.height)"
                updatePreview()
            } catch {
                guard loadID == id else { return }
                loading = false; self.error = error.localizedDescription
            }
        }
    }

    func setAdjusting(_ value: Bool) {
        guard isAdjusting != value else { return }
        isAdjusting = value
        updatePreview()
    }

    func updatePreview() {
        renderRevision += 1
        guard source != nil, !loading, renderTask == nil else { return }
        rendering = true
        // One in-flight render. Changes arriving during it are coalesced into the
        // next snapshot, rather than spawning unstructured work for every event.
        renderTask = Task {
            defer { renderTask = nil; rendering = false }
            while let source, !loading {
                let revision = renderRevision
                let currentLoadID = loadID
                let current = settings
                let size = isAdjusting ? 512 : 1024
                do {
                    let image = try await Task.detached(priority: .userInitiated) {
                        try autoreleasepool {
                            try IconRenderer.render(source, settings: current, size: size)
                        }
                    }.value
                    // Keep intermediate frames visible during dragging, but never
                    // publish an old document after a different file is opened.
                    if currentLoadID == loadID { output = image }
                } catch {
                    if currentLoadID == loadID, revision == renderRevision {
                        self.error = error.localizedDescription
                    }
                }
                if revision == renderRevision { break }
            }
        }
    }

    func export(icns: Bool) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = icns ? [.icns] : [.png]
        panel.nameFieldStringValue = "\(filename).\(icns ? "icns" : "png")"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = settings
        busy = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    // Render the current settings rather than a potentially older preview.
                    let image = try IconRenderer.render(source, settings: snapshot)
                    if icns { try IconExporter.exportICNS(image, to: url) }
                    else { try IconExporter.exportPNG(image, to: url) }
                }.value
                busy = false
                status = String(format: String(localized: "Exported %@"), url.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }
}

enum IconPreset: String, Sendable { case macOS26, macOS27, custom }

struct ContentView: View {
    @Bindable var model: EditorModel
    @State private var darkBackground = false
    @State private var comparison = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    (darkBackground ? Color(white: 0.14) : Color(white: 0.92))
                    if let source = model.source {
                        HStack(spacing: 0) {
                            if comparison {
                                preview(source.image, label: "Original", edge: previewEdge(geo.size))
                            }
                            if let output = model.output {
                                preview(output, label: "Processed", edge: previewEdge(geo.size))
                            }
                        }.padding(20)
                    } else {
                        ContentUnavailableView {
                            Label("Drop an Image or App", systemImage: "square.dashed")
                        } description: {
                            Text("Images or .app")
                        } actions: {
                            Button("Open…") { model.open() }.keyboardShortcut("o")
                        }
                    }
                    if targeted {
                        Rectangle().stroke(.tint, lineWidth: 4)
                            .background(.tint.opacity(0.08)).allowsHitTesting(false)
                    }
                    if model.loading {
                        ProgressView("Opening…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .clipped()
                // The canvas has its own background independent of the window's
                // appearance. Resolve semantic text/control colors in that scheme.
                .environment(\.colorScheme, darkBackground ? .dark : .light)
            }
            Divider()
            HStack(spacing: 8) {
                if model.rendering { ProgressView().controlSize(.mini) }
                Text(model.status).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.source != nil { Text("1024 × 1024").monospacedDigit() }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
        }
        .navigationTitle("Icon Shadow")
        .inspector(isPresented: .constant(true)) {
            inspector.inspectorColumnWidth(min: 280, ideal: 310, max: 350)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Open…", systemImage: "folder") { model.open() }
                    .help("Open Image or App (⌘O)").disabled(model.loading)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $comparison) { Label("Compare", systemImage: "rectangle.split.2x1") }
                    .help("Compare the original and processed icon").disabled(model.source == nil)
                    .toggleStyle(.button)
                    .labelStyle(.titleAndIcon)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    darkBackground.toggle()
                } label: {
                    Label("Background", systemImage: darkBackground ? "sun.max" : "moon")
                }
                .labelStyle(.titleAndIcon)
                .help(darkBackground ? "Switch to Light Background" : "Switch to Dark Background")
                .accessibilityLabel(darkBackground ? Text("Switch to Light Background") : Text("Switch to Dark Background"))
            }
        }
        .onChange(of: model.settings) {
            if model.settings != IconSettings() { model.preset = .custom }
            model.updatePreview()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.load(url) } }
            }
            return true
        }
        .alert("Unable to Complete the Operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay(alignment: .bottom) {
            if model.busy { ProgressView("Exporting…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding() }
        }
    }

    private func previewEdge(_ size: CGSize) -> CGFloat {
        max(1, min(size.width / (comparison ? 2 : 1) - 40, size.height - 80))
    }

    private func preview(_ image: CGImage, label: LocalizedStringKey, edge: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: edge, height: edge)
            if comparison {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        Form {
            Section {
                Picker("Preset", selection: Binding(get: { model.preset }, set: { model.applyPreset($0) })) {
                    Text("macOS 26").tag(IconPreset.macOS26)
                    Text("macOS 27").tag(IconPreset.macOS27)
                    if model.preset == .custom { Text("Custom").tag(IconPreset.custom) }
                }
                .labelsHidden()
                .help("Both versions use the same measured static outline and shadow. Glass materials are already baked into your artwork.")
            } header: {
                HStack {
                    Text("Preset")
                    Spacer()
                    Button("Reset to Defaults") { model.reset() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(model.settings == IconSettings())
                }
            }
            Section("Artwork") {
                parameter("Artwork Scale", value: $model.settings.scale, range: 30...100, unit: "%")
                parameter("Horizontal Position", value: $model.settings.horizontal, range: -180...180)
                parameter("Vertical Position", value: $model.settings.vertical, range: -180...180)
            }
            Section("Shadow") {
                parameter("Shadow Opacity", value: $model.settings.shadowOpacity, range: 0...0.7, unit: "%", multiplier: 100)
                parameter("Shadow Blur", value: $model.settings.shadowBlur, range: 0...60)
                parameter("Shadow Offset", value: $model.settings.shadowOffset, range: -40...60)
            }
            Section {
                Toggle("Fit to Mask", isOn: $model.settings.fitToMask)
                    .help("Fit to the native continuous-corner mask while preserving the artwork’s proportions.")
                Toggle("Trim Transparent Edges", isOn: $model.settings.trimTransparentEdges)
                    .help("Remove transparent padding before scaling the artwork.")
            } footer: {
                Text("If the icon already has a shadow, set Shadow Opacity to 0.")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Button { model.export(icns: false) } label: {
                        Text("Export PNG…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { model.export(icns: true) } label: {
                        Text("Export ICNS…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .disabled(model.output == nil || model.busy || model.loading)
                .padding(16)
            }
            .background(.bar)
        }
    }

    private func parameter(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "px", multiplier: Double = 1) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * multiplier).rounded()))\(unit == "%" ? "%" : " px")")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, onEditingChanged: model.setAdjusting)
                .controlSize(.small).accessibilityLabel(title)
        }.padding(.vertical, 3)
    }
}
