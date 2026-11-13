import Foundation

enum SetupStep: Equatable {
    case checking, library, preferences, attention, ready
}

func setupStep(for state: AgentState) -> SetupStep {
    if state.busy || state.lastCheckAt == nil { return .checking }
    if state.libraryReady == false { return .library }
    if state.libraryReady == true && state.prefetchReady == false { return .preferences }
    if state.libraryReady != true || state.prefetchReady != true || !state.cleanupAllowed { return .attention }
    return .ready
}

enum LaunchDestination: Equatable {
    case background, setup, settings
}

func launchDestination(arguments: [String], setupCompleted: Bool, loginItem: Bool = false) -> LaunchDestination {
    if loginItem { return .background }
    if arguments.contains("--setup") { return .setup }
    if arguments.contains("--background") { return .background }
    return setupCompleted ? .settings : .setup
}

enum PaneInstallationError: LocalizedError {
    case invalidPane, unexpectedDestination

    var errorDescription: String? {
        switch self {
        case .invalidPane: return "The settings pane is missing or incomplete. Download Photos Storage again."
        case .unexpectedDestination: return "An unexpected item occupies the Photos Storage settings location. It has been left unchanged."
        }
    }
}

struct PaneInstallation {
    static let identifier = "nl.emieljanson.PhotosStorage.Settings"

    static var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/PreferencePanes/PhotosStorage.prefPane", isDirectory: true)
    }

    static func isPane(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == identifier,
              info["CFBundleExecutable"] as? String == "PhotosStoragePane" else { return false }
        return FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/PhotosStoragePane").path)
    }

    static func install(from source: URL, to destination: URL = destination) throws {
        let files = FileManager.default
        guard isPane(source) else { throw PaneInstallationError.invalidPane }
        if files.fileExists(atPath: destination.path) {
            guard isPane(destination) else { throw PaneInstallationError.unexpectedDestination }
            if files.contentsEqual(atPath: source.path, andPath: destination.path) { return }
        }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".PhotosStorage-\(UUID().uuidString).prefPane")
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: source, to: staged)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: staged)
        } else {
            try files.moveItem(at: staged, to: destination)
        }
    }
}
