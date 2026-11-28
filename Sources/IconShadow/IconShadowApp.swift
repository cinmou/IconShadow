import SwiftUI
import AppKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import IconShadowCore
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?
    var openFileURL: ((URL) -> Void)?
    private var pendingURL: URL?

    func bind(reopen: @escaping () -> Void, openFile: @escaping (URL) -> Void) {
        reopenMainWindow = reopen
        openFileURL = openFile
        if let url = pendingURL {
            pendingURL = nil
            reopen()
            openFile(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenMainWindow?() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: \.isFileURL) else { return }
        if let openFileURL {
            reopenMainWindow?()
            openFileURL(url)
        } else {
            pendingURL = url
        }
    }
}

@main
struct IconShadowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var model = EditorModel()
    var body: some Scene {
        Window("Icon Shadow", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 580)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    openWindow(id: "main")
                    model.load(url)
                }
                .task {
                    let openMain = openWindow
                    let editor = model
                    appDelegate.bind(
                        reopen: { openMain(id: "main") },
                        openFile: { editor.load($0) }
                    )
                }
        }
        .defaultSize(width: 1020, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", systemImage: "folder") {
                    if NSApp.keyWindow == nil {
                        openWindow(id: "main")
                        Task { @MainActor in model.open() }
                    } else {
                        model.open()
                    }
                }.keyboardShortcut("o")
                if model.mode == .folder {
                    Button("Apply to Folder…", systemImage: "folder.badge.plus") {
                        model.applyToFolder()
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.output == nil || model.busy || model.loading)
                }
                Button("Export ICNS…") { model.export(icns: true) }
                    .keyboardShortcut("e").disabled(model.output == nil || model.busy || model.loading)
                Button("Export PNG…") { model.export(icns: false) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.output == nil || model.busy || model.loading)
            }
        }
    }
}

enum EditorMode: String, CaseIterable, Sendable {
    case appIcon
    case folder
}

enum CanvasAppearance: String, CaseIterable, Sendable {
    case auto
    case light
    case dark

    var next: CanvasAppearance {
        switch self {
        case .auto: .light
        case .light: .dark
        case .dark: .auto
        }
    }

    var symbolName: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var helpText: LocalizedStringKey {
        switch self {
        case .auto: "Background: Auto"
        case .light: "Background: Light"
        case .dark: "Background: Dark"
        }
    }
}

enum IconPreset: String, Sendable { case macOS26, macOS27, custom }

@MainActor @Observable
final class EditorModel {
    private static let defaultPreset: IconPreset = ProcessInfo.processInfo.operatingSystemVersion.majorVersion <= 26 ? .macOS26 : .macOS27
    var mode: EditorMode = .appIcon
    var source: IconSource?
    var output: CGImage?
    var filename = ""
    var settings = IconSettings()
    var preset: IconPreset = EditorModel.defaultPreset

    var folderSettings = FolderSettings()
    var folderBase: FolderBaseMetrics?
    var selectedSymbolName: String?
    var symbolSource: IconSource?
    var folderUsesSymbol = false
    var folderUsesEmpty = false

    var busy = false
    var loading = false
    var rendering = false
    var error: String?
    var status = String(localized: "Image or App")
    private var renderTask: Task<Void, Never>?
    private var loadID = UUID()
    private var loadingURL: URL?
    private var renderRevision = 0
    private var isAdjusting = false
    private var activeFilePanel: NSSavePanel?

    var activeFolderArtwork: IconSource? {
        if folderUsesEmpty { return nil }
        if folderUsesSymbol { return symbolSource }
        return source
    }

    var comparisonOriginal: CGImage? {
        switch mode {
        case .appIcon: source?.image
        case .folder: folderBase?.baseImage
        }
    }

    var canCompare: Bool {
        comparisonOriginal != nil && output != nil
    }

    var hasCanvasContent: Bool {
        mode == .folder || source != nil
    }

    var folderEmblemSummary: String {
        if folderUsesEmpty { return String(localized: "None") }
        if folderUsesSymbol, let selectedSymbolName { return selectedSymbolName }
        if source != nil, !filename.isEmpty { return filename }
        return String(localized: "None")
    }

    var canRestoreFileInFolder: Bool {
        source != nil && (folderUsesSymbol || folderUsesEmpty)
    }

    func switchMode(_ newMode: EditorMode) {
        guard mode != newMode else { return }
        mode = newMode
        if newMode == .folder {
            ensureFolderBase()
            updateFolderStatus()
            updatePreview()
        } else {
            if let source {
                status = "\(filename) · \(source.width) × \(source.height)"
                updatePreview()
            } else {
                output = nil
                status = String(localized: "Image or App")
            }
        }
    }

    func ensureFolderBase() {
        guard folderBase == nil else { return }
        do {
            folderBase = try FolderIconRenderer.prepareSystemFolderBase()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyPreset(_ value: IconPreset) {
        preset = value
        if value != .custom { settings = IconSettings() }
    }

    func reset() {
        if preset == .custom { preset = Self.defaultPreset }
        settings = IconSettings()
    }

    func resetFolderSettings() {
        let keepStyle = folderSettings.style
        folderSettings = FolderSettings()
        folderSettings.style = keepStyle
        updatePreview()
    }

    func selectSymbol(_ name: String) {
        do {
            let loaded = try FolderIconRenderer.loadSymbol(name)
            selectedSymbolName = name
            symbolSource = loaded
            folderUsesSymbol = true
            folderUsesEmpty = false
            folderSettings.style = .embossed
            if mode != .folder { mode = .folder }
            ensureFolderBase()
            updateFolderStatus()
            updatePreview()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func useDroppedArtworkInFolder() {
        guard source != nil else { return }
        folderUsesSymbol = false
        folderUsesEmpty = false
        updateFolderStatus()
        updatePreview()
    }

    func clearFolderEmblem() {
        folderUsesEmpty = true
        folderUsesSymbol = false
        selectedSymbolName = nil
        symbolSource = nil
        updateFolderStatus()
        updatePreview()
    }

    private func updateFolderStatus() {
        if folderUsesEmpty {
            status = String(localized: "Empty Folder")
        } else if folderUsesSymbol, let selectedSymbolName {
            status = "\(String(localized: "Folder")) · \(selectedSymbolName)"
        } else if let source {
            status = "\(String(localized: "Folder")) · \(filename) (\(source.width) × \(source.height))"
        } else {
            status = String(localized: "Empty Folder")
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconRenderer.supportedImageTypes + NativeIconImporter.vectorTypes + [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        presentFilePanel(panel) { [weak self] response in
            if response == .OK, let url = panel.url { self?.load(url) }
        }
    }

    /// Attach file dialogs to the editor without entering a nested application-modal
    /// event loop from a SwiftUI button action. Keep only one panel active at a time.
    private func presentFilePanel(_ panel: NSSavePanel,
                                  completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let activeFilePanel {
            activeFilePanel.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if let sheet = window?.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
            return
        }
        activeFilePanel = panel
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.activeFilePanel = nil
            completion(response)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            // A menu command may arrive before the editor has a key window.
            panel.begin(completionHandler: finish)
        }
    }

    func load(_ url: URL) {
        let standardized = url.standardizedFileURL
        if loading, loadingURL == standardized { return }
        let id = UUID(); loadID = id
        loadingURL = standardized
        loading = true
        let isApp = url.pathExtension.lowercased() == "app"
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
                let baseName = url.deletingPathExtension().lastPathComponent
                source = loaded; filename = baseName.isEmpty ? "Icon" : baseName
                folderUsesSymbol = false
                folderUsesEmpty = false
                if isApp { folderSettings.style = .appLogo }
                loading = false; loadingURL = nil; output = nil
                if mode == .folder {
                    ensureFolderBase()
                    updateFolderStatus()
                } else {
                    status = "\(url.lastPathComponent) · \(loaded.width) × \(loaded.height)"
                }
                updatePreview()
            } catch {
                guard loadID == id else { return }
                loading = false; loadingURL = nil; self.error = error.localizedDescription
                if hasCanvasContent, output == nil { updatePreview() }
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
        if mode == .folder { ensureFolderBase() }
        guard hasCanvasContent, !loading, renderTask == nil else { return }
        if mode == .folder, folderBase == nil { return }
        rendering = true
        // One in-flight render. Changes arriving during it are coalesced into the
        // next snapshot, rather than spawning unstructured work for every event.
        renderTask = Task {
            defer { renderTask = nil; rendering = false }
            renderLoop: while hasCanvasContent, !loading {
                let revision = renderRevision
                let currentLoadID = loadID
                let currentMode = mode
                let size = isAdjusting ? 512 : 1024
                do {
                    let image: CGImage
                    switch currentMode {
                    case .appIcon:
                        guard let source else { break renderLoop }
                        let current = settings
                        image = try await Task.detached(priority: .userInitiated) {
                            try autoreleasepool {
                                try IconRenderer.render(source, settings: current, size: size)
                            }
                        }.value
                    case .folder:
                        guard let base = folderBase else { break renderLoop }
                        let artwork = activeFolderArtwork
                        let current = folderSettings
                        image = try await Task.detached(priority: .userInitiated) {
                            try autoreleasepool {
                                try FolderIconRenderer.render(source: artwork, base: base, settings: current, size: size)
                            }
                        }.value
                    }
                    // Keep intermediate frames visible during dragging, but never
                    // publish an old document after a different file is opened.
                    if currentLoadID == loadID, currentMode == mode { output = image }
                } catch {
                    if currentLoadID == loadID, revision == renderRevision {
                        self.error = error.localizedDescription
                    }
                }
                if revision == renderRevision { break }
            }
        }
    }

    private func defaultExportBaseName() -> String {
        switch mode {
        case .appIcon:
            return filename.isEmpty ? "Icon" : filename
        case .folder:
            if folderUsesEmpty { return "Folder" }
            if folderUsesSymbol, let selectedSymbolName { return selectedSymbolName }
            return filename.isEmpty ? "Folder" : filename
        }
    }

    func export(icns: Bool) {
        guard !busy, !loading else { return }
        let currentMode = mode
        if currentMode == .appIcon, source == nil { return }
        if currentMode == .folder {
            ensureFolderBase()
            guard folderBase != nil else { return }
        }
        let appSource = source
        let appSnapshot = settings
        let folderArtwork = activeFolderArtwork
        let folderSnapshot = folderSettings
        let base = folderBase

        let panel = NSSavePanel()
        panel.allowedContentTypes = icns ? [.icns] : [.png]
        panel.nameFieldStringValue = "\(defaultExportBaseName()).\(icns ? "icns" : "png")"
        panel.canCreateDirectories = true
        presentFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writeExport(
                mode: currentMode,
                appSource: appSource,
                appSettings: appSnapshot,
                folderArtwork: folderArtwork,
                folderBase: base,
                folderSettings: folderSnapshot,
                to: url,
                icns: icns
            )
        }
    }

    private func writeExport(
        mode currentMode: EditorMode,
        appSource: IconSource?,
        appSettings: IconSettings,
        folderArtwork: IconSource?,
        folderBase: FolderBaseMetrics?,
        folderSettings: FolderSettings,
        to url: URL,
        icns: Bool
    ) {
        busy = true
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let image: CGImage
                    switch currentMode {
                    case .appIcon:
                        guard let appSource else { throw IconError.renderingFailed }
                        image = try IconRenderer.render(appSource, settings: appSettings)
                    case .folder:
                        guard let folderBase else { throw IconError.renderingFailed }
                        image = try FolderIconRenderer.render(source: folderArtwork, base: folderBase, settings: folderSettings)
                    }
                    if icns { try IconExporter.exportICNS(image, to: url) }
                    else { try IconExporter.exportPNG(image, to: url) }
                }.value
                busy = false
                status = String(format: String(localized: "Exported %@"), url.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }

    func applyToFolder() {
        guard mode == .folder, !busy, !loading else { return }
        ensureFolderBase()
        guard let base = folderBase else { return }
        let artwork = activeFolderArtwork
        let snapshot = folderSettings

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Apply Icon")
        panel.message = String(localized: "Choose a folder to apply this icon.")
        presentFilePanel(panel) { [weak self] response in
            guard response == .OK, let folderURL = panel.url else { return }
            self?.performApplyToFolder(artwork: artwork, base: base, settings: snapshot, folderURL: folderURL)
        }
    }

    private func performApplyToFolder(
        artwork: IconSource?,
        base: FolderBaseMetrics,
        settings snapshot: FolderSettings,
        folderURL: URL
    ) {
        busy = true
        Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try FolderIconRenderer.render(source: artwork, base: base, settings: snapshot)
                }.value
                try IconExporter.applyToFolder(image, folderURL: folderURL)
                busy = false
                status = String(format: String(localized: "Applied to %@"), folderURL.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            } catch {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }
}

struct ContentView: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var canvasAppearance: CanvasAppearance = .auto
    @State private var comparison = false
    @State private var targeted = false
    @State private var showingSymbolPicker = false

    private var isDarkCanvas: Bool {
        switch canvasAppearance {
        case .auto: systemColorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    (isDarkCanvas ? Color(white: 0.14) : Color(white: 0.92))
                    if model.hasCanvasContent {
                        HStack(spacing: 0) {
                            if comparison, let original = model.comparisonOriginal {
                                preview(original, label: "Original", edge: previewEdge(geo.size))
                            }
                            if let output = model.output {
                                preview(output, label: "Processed", edge: previewEdge(geo.size))
                            }
                        }.padding(20)
                    } else {
                        ContentUnavailableView {
                            Label("Drop Image or App", systemImage: "square.dashed")
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
                .environment(\.colorScheme, isDarkCanvas ? .dark : .light)
            }
            Divider()
            HStack(spacing: 8) {
                if model.rendering { ProgressView().controlSize(.mini) }
                Text(model.status).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.hasCanvasContent { Text("1024 × 1024").monospacedDigit() }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
        }
        .navigationTitle("Icon Shadow")
        .inspector(isPresented: .constant(true)) {
            inspector.inspectorColumnWidth(min: 260, ideal: 280, max: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Open…", systemImage: "folder") { model.open() }
                    .labelStyle(.iconOnly)
                    .help("Open Image or App (⌘O)").disabled(model.loading)
            }
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: Binding(get: { model.mode }, set: { model.switchMode($0) })) {
                    Text("App Icon").tag(EditorMode.appIcon)
                    Text("Folder").tag(EditorMode.folder)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $comparison) { Label("Compare", systemImage: "rectangle.split.2x1") }
                    .help("Compare the original and processed icon").disabled(!model.canCompare)
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    canvasAppearance = canvasAppearance.next
                } label: {
                    Label("Background", systemImage: canvasAppearance.symbolName)
                }
                .labelStyle(.iconOnly)
                .help(canvasAppearance.helpText)
                .accessibilityLabel(Text(canvasAppearance.helpText))
            }
        }
        .onChange(of: model.settings) {
            if model.settings != IconSettings() { model.preset = .custom }
            if model.mode == .appIcon { model.updatePreview() }
        }
        .onChange(of: model.folderSettings) {
            if model.mode == .folder { model.updatePreview() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            model.load(url)
            return true
        } isTargeted: { targeted = $0 }
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
            if model.mode == .appIcon {
                appIconInspectorSections
            } else {
                folderInspectorSections
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 8) {
                    if model.mode == .folder {
                        Button { model.applyToFolder() } label: {
                            Label("Apply to Folder…", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 8) {
                        Button { model.export(icns: false) } label: {
                            Text("PNG…").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .help("Export PNG… (⇧⌘E)")
                        Button { model.export(icns: true) } label: {
                            Text("ICNS…").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .help("Export ICNS… (⌘E)")
                    }
                }
                .controlSize(.large)
                .disabled(model.output == nil || model.busy || model.loading)
                .padding(14)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private var appIconInspectorSections: some View {
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
                Button("Reset") { model.reset() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(model.settings == IconSettings())
            }
        }
        Section("Artwork") {
            parameter("Scale", value: $model.settings.scale, range: 30...100, unit: "%")
            parameter("X", value: $model.settings.horizontal, range: -180...180)
            parameter("Y", value: $model.settings.vertical, range: -180...180)
        }
        Section("Shadow") {
            parameter("Opacity", value: $model.settings.shadowOpacity, range: 0...0.7, unit: "%", multiplier: 100)
            parameter("Blur", value: $model.settings.shadowBlur, range: 0...60)
            parameter("Offset", value: $model.settings.shadowOffset, range: -40...60)
        }
        Section {
            Toggle("Round Mask", isOn: $model.settings.fitToMask)
                .help("Fit to the native continuous-corner mask while preserving the artwork’s proportions.")
            Toggle("Trim Edges", isOn: $model.settings.trimTransparentEdges)
                .help("Remove transparent padding before scaling the artwork.")
        }
    }

    @ViewBuilder
    private var folderInspectorSections: some View {
        Section {
            Picker("Style", selection: $model.folderSettings.style) {
                Text("Logo").tag(FolderStyle.appLogo)
                Text("Embossed").tag(FolderStyle.embossed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                Text("Emblem")
                Spacer()
                Button {
                    showingSymbolPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.folderUsesSymbol ? (model.selectedSymbolName ?? "sparkles") : "square.grid.2x2")
                            .font(.system(size: 11, weight: .medium))
                        Text(model.folderEmblemSummary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                }
                .controlSize(.small)
                .help("Symbols…")
                .popover(isPresented: $showingSymbolPicker, arrowEdge: .leading) {
                    SymbolPickerView(selected: model.selectedSymbolName) { name in
                        model.selectSymbol(name)
                        showingSymbolPicker = false
                    }
                }
                if model.canRestoreFileInFolder {
                    Button {
                        model.useDroppedArtworkInFolder()
                    } label: {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(format: String(localized: "Use Dropped File (%@)"), model.filename))
                }
                if model.activeFolderArtwork != nil {
                    Button {
                        model.clearFolderEmblem()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Emblem")
                    .accessibilityLabel("Clear Emblem")
                }
            }
        } header: {
            HStack {
                Text("Style")
                Spacer()
                Button("Reset") { model.resetFolderSettings() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(isDefaultFolderSettings)
            }
        }

        Section("Folder") {
            FolderColorPaletteView(
                preset: $model.folderSettings.colorPreset,
                customColor: $model.folderSettings.customColor
            )
            Toggle("Paper Sheet", isOn: $model.folderSettings.hasFiles)
                .help("Show a white paper sheet tucked inside the folder, matching non-empty macOS folders.")
        }

        Section("Layout") {
            parameter("Scale", value: $model.folderSettings.scale, range: 15...65, unit: "%")
            parameter("X", value: $model.folderSettings.horizontal, range: -220...220)
            parameter("Y", value: $model.folderSettings.vertical, range: -220...220)
            if model.folderSettings.style == .embossed {
                parameter("Depth", value: $model.folderSettings.embossDepth, range: 0...1.5, unit: "%", multiplier: 100)
                parameter("Threshold", value: $model.folderSettings.embossThreshold, range: 0...1, unit: "%", multiplier: 100)
            } else {
                parameter("Shadow", value: $model.folderSettings.badgeShadowOpacity, range: 0...0.6, unit: "%", multiplier: 100)
                Toggle("Round Corners", isOn: $model.folderSettings.roundLogoCorners)
                    .help("Clip square artwork with native continuous corners.")
            }
            Toggle("Trim Edges", isOn: $model.folderSettings.trimTransparentEdges)
                .help("Remove transparent padding before scaling the artwork.")
        }
    }

    private var isDefaultFolderSettings: Bool {
        var reference = FolderSettings()
        reference.style = model.folderSettings.style
        return model.folderSettings == reference
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

private struct FolderColorPaletteView: View {
    @Binding var preset: FolderColorPreset
    @Binding var customColor: FolderRGB

    private let presets: [FolderColorPreset] = [
        .systemDefault, .skyBlue, .blue, .purple, .pink,
        .red, .orange, .yellow, .green, .graphite,
    ]

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(.sRGB, red: customColor.red, green: customColor.green, blue: customColor.blue, opacity: 1)
            },
            set: { newValue in
                if let srgb = NSColor(newValue).usingColorSpace(.sRGB) {
                    customColor = FolderRGB(
                        red: Double(srgb.redComponent),
                        green: Double(srgb.greenComponent),
                        blue: Double(srgb.blueComponent)
                    )
                    preset = .custom
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(presets) { item in
                    Button {
                        preset = item
                    } label: {
                        swatch(for: item, selected: preset == item)
                    }
                    .buttonStyle(.plain)
                    .help(label(for: item))
                    .accessibilityLabel(label(for: item))
                }
                ZStack {
                    ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom Color")
                    if preset == .custom {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(width: 26, height: 26)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 26, height: 26)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func swatch(for item: FolderColorPreset, selected: Bool) -> some View {
        ZStack {
            if item == .systemDefault {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.sRGB, red: 0.45, green: 0.82, blue: 0.98), Color(.sRGB, red: 0.25, green: 0.68, blue: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            } else if let rgb = item.targetRGB {
                Circle()
                    .fill(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue))
                    .frame(width: 20, height: 20)
            }
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 26, height: 26)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func label(for item: FolderColorPreset) -> LocalizedStringKey {
        switch item {
        case .systemDefault: "System Default"
        case .skyBlue: "Sky Blue"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        case .custom: "Custom Color"
        }
    }
}

private struct SymbolPickerView: View {
    let selected: String?
    let onSelect: (String) -> Void
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [FolderSymbolPreset] {
        guard !trimmedQuery.isEmpty else { return FolderIconRenderer.curatedSymbols }
        let q = trimmedQuery.lowercased()
        return FolderIconRenderer.curatedSymbols.filter {
            $0.name.lowercased().contains(q) || $0.keywords.lowercased().contains(q)
        }
    }

    private var exactCustomSymbol: String? {
        guard !trimmedQuery.isEmpty,
              !FolderIconRenderer.curatedSymbols.contains(where: { $0.name == trimmedQuery }),
              FolderIconRenderer.isValidSymbol(trimmedQuery)
        else { return nil }
        return trimmedQuery
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search or enter SF Symbol name…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let exact = exactCustomSymbol {
                        onSelect(exact)
                    } else if let first = filtered.first {
                        onSelect(first.name)
                    }
                }

            if let exact = exactCustomSymbol {
                Button {
                    onSelect(exact)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: exact)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 22)
                        Text(exact).lineLimit(1)
                        Spacer()
                        Text("Use Symbol").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(filtered) { item in
                        Button {
                            onSelect(item.name)
                        } label: {
                            Image(systemName: item.name)
                                .font(.system(size: 18, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(
                                    selected == item.name ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .overlay {
                                    if selected == item.name {
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(width: 300, height: 340)
    }
}
