import AppKit
import SwiftUI

@MainActor
final class CloudDownloadsModel: ObservableObject {
    struct Row: Identifiable {
        let url: URL
        var snapshot: CloudFileSnapshot?
        var message: String
        var pending = true
        var id: URL { url }
    }

    @Published var rows: [Row] = []
    @Published var busy = false
    @Published var summary: String?
    private var task: Task<Void, Never>?
    var didFinish: (() -> Void)?
    var ready: [Row] { rows.filter { $0.snapshot?.decision == .ready && $0.snapshot?.identity != nil } }

    func chooseFiles(window: NSWindow?) {
        guard !busy, let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose iCloud Downloads"
        panel.message = "Choose individual files in iCloud Drive. Their upload status is checked before any downloads are removed."
        panel.prompt = "Review Downloads"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.inspect(panel.urls)
        }
    }

    func inspect(_ urls: [URL]) {
        guard !busy else { return }
        summary = nil
        rows = Array(Set(urls)).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Row(url: $0, message: "Checking iCloud…") }
        busy = true
        let executable = Bundle.main.executableURL!
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if Task.isCancelled {
                    for index in self.rows.indices where self.rows[index].pending {
                        self.rows[index].message = "Not checked. Choose files again."
                        self.rows[index].pending = false
                    }
                }
                self.busy = false
                self.didFinish?()
            }
            for index in self.rows.indices {
                guard !Task.isCancelled else { return }
                let url = self.rows[index].url
                let result = await Task.detached { runCloudFileWorker(executable: executable, url: url) }.value
                self.rows[index].snapshot = result.error == nil ? result.snapshot : nil
                self.rows[index].message = result.error ?? result.snapshot?.decision.message ?? "Unable to confirm iCloud upload"
                self.rows[index].pending = false
            }
        }
    }

    func removeDownloads() {
        guard !busy, !ready.isEmpty else { return }
        busy = true
        summary = nil
        let executable = Bundle.main.executableURL!
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.didFinish?() }
            var reduced: Int64 = 0
            for index in self.rows.indices {
                guard !Task.isCancelled else { return }
                guard let snapshot = self.rows[index].snapshot, snapshot.decision == .ready,
                      let identity = snapshot.identity else { continue }
                let url = self.rows[index].url
                self.rows[index].message = "Removing local download…"
                let result = await Task.detached { runCloudFileWorker(executable: executable, url: url, identity: identity) }.value
                self.rows[index].snapshot = result.error == nil ? result.snapshot : nil
                self.rows[index].message = result.error ?? result.snapshot?.decision.message ?? "Check again before retrying"
                reduced += result.reducedBytes
            }
            if reduced > 0 {
                self.summary = "Local downloads reduced by \(ByteCountFormatter.string(fromByteCount: reduced, countStyle: .file)). Files remain in iCloud."
            } else { self.summary = "No download removal was confirmed. Review the file status before trying again." }
        }
    }

    func cancelRemaining() { task?.cancel() }
}

private struct CloudDownloadsView: View {
    @ObservedObject var model: CloudDownloadsModel
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iCloud Downloads").font(.title2).fontWeight(.semibold)
            Text("Free local copies of files you choose. Files stay in iCloud and download again when opened.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "icloud").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Choose files to review their local downloads.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.snapshot?.decision == .cloudOnly ? "icloud" : "doc")
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.url.lastPathComponent).lineLimit(1).truncationMode(.middle).help(row.url.path)
                            Text(row.message).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let snapshot = row.snapshot, snapshot.decision == .ready {
                            Text(ByteCountFormatter.string(fromByteCount: snapshot.allocatedBytes, countStyle: .file))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                .listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let summary = model.summary {
                Text(summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Choose Files…", action: choose).disabled(model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Checking iCloud downloads") }
                Button("Remove Downloads") { model.removeDownloads() }
                    .disabled(model.busy || model.ready.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(minWidth: 480, minHeight: 340)
    }
}

@MainActor
final class CloudDownloadsWindowController: NSWindowController, NSWindowDelegate {
    let model = CloudDownloadsModel()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "iCloud Downloads"
        window.contentMinSize = NSSize(width: 480, height: 340)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CloudDownloadsView(model: model, choose: { [weak self] in
            self?.model.chooseFiles(window: self?.window)
        }))
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.cancelRemaining() }
}
