import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

var state = AgentState()
expect(setupStep(for: state) == .checking, "New installs must wait for a real access check")
state.lastCheckAt = Date().timeIntervalSince1970
state.libraryReady = false
state.prefetchReady = false
expect(setupStep(for: state) == .library, "Ask for the library first")
state.libraryReady = true
expect(setupStep(for: state) == .preferences, "Ask for only the remaining permission")
state.prefetchReady = true
expect(setupStep(for: state) == .attention, "Permissions alone must not claim safe setup")
state.cleanupAllowed = true
expect(setupStep(for: state) == .ready, "Confirmed access and safety finish setup")
state.busy = true
expect(setupStep(for: state) == .checking, "Never request another permission during a check")
state.busy = false
state.libraryReady = nil
expect(setupStep(for: state) == .attention, "Unknown access must never be treated as granted")
state.prefetchReady = false
expect(setupStep(for: state) == .attention, "Unknown library access must not skip ahead to the settings permission")

expect(launchDestination(arguments: [], setupCompleted: false) == .setup, "First interactive launch needs setup")
expect(launchDestination(arguments: [], setupCompleted: true) == .settings, "Later launches open Settings")
expect(launchDestination(arguments: ["--background"], setupCompleted: false) == .background, "Login and pane launches must stay silent")
expect(launchDestination(arguments: ["--setup"], setupCompleted: true) == .setup, "People can revisit setup")
expect(launchDestination(arguments: [], setupCompleted: false, loginItem: true) == .background, "Login must never interrupt with onboarding")
expect(launchDestination(arguments: [], setupCompleted: true, loginItem: true) == .background, "Login must never open Settings")

let files = FileManager.default
let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? files.removeItem(at: root) }
let source = root.appendingPathComponent("Source.prefPane")
let destination = root.appendingPathComponent("Installed/PhotosStorage.prefPane")
try files.createDirectory(at: source.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
let info: [String: String] = ["CFBundleIdentifier": PaneInstallation.identifier, "CFBundleExecutable": "PhotosStoragePane"]
let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
try data.write(to: source.appendingPathComponent("Contents/Info.plist"))
let executable = source.appendingPathComponent("Contents/MacOS/PhotosStoragePane")
try Data("first version".utf8).write(to: executable)
try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
try PaneInstallation.install(from: source, to: destination)
expect(files.contentsEqual(atPath: source.path, andPath: destination.path), "A fresh install must include the complete pane")
try PaneInstallation.install(from: source, to: destination)
expect(files.contentsEqual(atPath: source.path, andPath: destination.path), "Identical installs must be harmless")
try Data("updated version".utf8).write(to: executable)
try PaneInstallation.install(from: source, to: destination)
expect(try Data(contentsOf: destination.appendingPathComponent("Contents/MacOS/PhotosStoragePane")) == Data("updated version".utf8), "Updates must replace the previous pane")

let unexpected = root.appendingPathComponent("Unrelated.prefPane")
try files.createDirectory(at: unexpected, withIntermediateDirectories: true)
let personal = unexpected.appendingPathComponent("keep.txt")
try Data("keep".utf8).write(to: personal)
do {
    try PaneInstallation.install(from: source, to: unexpected)
    fatalError("An unrelated destination must not be replaced")
} catch PaneInstallationError.unexpectedDestination {}
expect(files.fileExists(atPath: personal.path), "Existing unrelated files must remain intact")
do {
    try PaneInstallation.install(from: unexpected, to: destination)
    fatalError("An incomplete source must never replace a working pane")
} catch PaneInstallationError.invalidPane {}
expect(try Data(contentsOf: destination.appendingPathComponent("Contents/MacOS/PhotosStoragePane")) == Data("updated version".utf8), "Failed installs must preserve the working pane")
print("PASS setup progression, launch routing, first install, update, and unrelated-file preservation")
