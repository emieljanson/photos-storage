import AppKit

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    let controller = CloudDownloadsWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) { controller.present() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CloudDownloadsPreview {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--cloud-file" {
            cloudFileWorkerMain(Array(CommandLine.arguments.dropFirst()))
        }
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
