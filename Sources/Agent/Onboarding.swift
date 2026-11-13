import AppKit
import SwiftUI

enum SetupAction {
    case start, primary, openPhotos, dismiss
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var state: AgentState
    @Published var started = false
    @Published var error: String?
    @Published var openingSettings = false
    @Published var automaticUpdates = true
    let action: (SetupAction) -> Void

    init(state: AgentState, action: @escaping (SetupAction) -> Void) {
        self.state = state
        self.action = action
    }

    var step: SetupStep { setupStep(for: state) }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    private var ready: Bool { model.started && model.step == .ready }
    private var attention: Bool { model.started && model.step == .attention }

    private var title: String {
        if !model.started { return "Photos Storage" }
        if ready { return "Ready in System Settings" }
        if attention { return "Setup Needs Attention" }
        return "Allow Access"
    }

    private var description: String {
        if !model.started { return "Set a local storage target for Photos. Your controls live in System Settings." }
        if ready { return "Choose a storage target and turn on Optimize storage. System Settings reopens directly to your controls." }
        if attention { return model.state.message }
        switch model.step {
        case .library: return "In the next window, your Photos library is selected. Click Allow Library to let Photos Storage measure its size."
        case .preferences: return "In the next window, the Photos settings file is selected. Click Allow Settings to manage optional downloads."
        default: return "Checking access to your Photos library and settings…"
        }
    }

    private var primaryTitle: String {
        if model.openingSettings { return "Opening…" }
        if !model.started { return "Continue" }
        switch model.step {
        case .checking: return "Checking…"
        case .library: return "Allow Photos Library…"
        case .preferences: return "Allow Photos Settings…"
        case .attention: return "Check Again"
        case .ready: return "Open System Settings"
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: ready ? "checkmark.circle.fill" : "photo.on.rectangle")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(ready ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                Text(title).font(.title2.bold())
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.started && !ready && !attention {
                VStack(alignment: .leading, spacing: 18) {
                    permission("Photos Library", detail: "Measure the space used by your local library.", granted: model.state.libraryReady == true)
                    permission("Photos Settings", detail: "Adjust how much Photos downloads in advance.", granted: model.state.prefetchReady == true)
                }
            } else {
                Label("System Settings › Photos Storage", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.started {
                Toggle("Keep Photos Storage up to date", isOn: $model.automaticUpdates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            HStack {
                if model.started && !ready {
                    Button("Back") { model.started = false; model.error = nil }
                } else {
                    Button("Not Now") { model.action(.dismiss) }
                }
                Spacer()
                if attention {
                    Button("Open Photos") { model.action(.openPhotos) }
                }
                if model.openingSettings || (model.started && model.step == .checking) {
                    ProgressView().controlSize(.small)
                }
                Button(primaryTitle) { model.action(model.started ? .primary : .start) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.openingSettings || (model.started && model.step == .checking))
            }
            .controlSize(.regular)
        }
        .padding(32)
        .frame(width: 480, height: 390)
    }

    private func permission(_ title: String, detail: String, granted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityLabel(granted ? "Allowed" : "Access needed")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class SetupWindowController: NSWindowController {
    let model: SetupModel

    init(model: SetupModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 390),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Photos Storage"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
