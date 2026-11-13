import AppKit
import Sparkle

@MainActor
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var started = false
    private var pendingInstallation: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private let isIdle: () -> Bool
    private let willRelaunch: () -> Void

    init(isIdle: @escaping () -> Bool, willRelaunch: @escaping () -> Void, stateDidChange: @escaping @MainActor @Sendable () -> Void) {
        self.isIdle = isIdle
        self.willRelaunch = willRelaunch
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { _, _ in
            Task { @MainActor in stateDidChange() }
        }
    }

    var enabled: Bool {
        controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func setEnabled(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func check() {
        start()
        guard canCheck else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func resumeInstallationIfIdle() {
        guard isIdle(), let install = pendingInstallation else { return }
        pendingInstallation = nil
        install()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !isIdle() else { return false }
        pendingInstallation = installHandler
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock installHandler: @escaping () -> Void) -> Bool {
        pendingInstallation = installHandler
        Task { @MainActor [weak self] in self?.resumeInstallationIfIdle() }
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { willRelaunch() }
}
