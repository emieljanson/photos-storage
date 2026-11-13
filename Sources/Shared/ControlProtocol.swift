import Foundation
import Darwin

enum ControlAction: String, Codable, Sendable {
    case setLimit, setAutomatic, setLogin, refresh, grantLibrary, grantPrefetch, openPhotos
}

struct ControlRequest: Codable, Sendable {
    let version: Int
    let id: UUID
    let sentAt: TimeInterval
    let action: ControlAction
    let value: Double?
    let enabled: Bool?

    func isValid(now: TimeInterval) -> Bool {
        guard version == 1, sentAt.isFinite, sentAt <= now + 60, sentAt >= now - 300 else { return false }
        switch action {
        case .setLimit: return value.map { $0.isFinite && $0 >= 0 && $0 <= 100_000 } == true && enabled == nil
        case .setAutomatic, .setLogin: return enabled != nil && value == nil
        default: return value == nil && enabled == nil
        }
    }
}

struct AgentState: Codable, Sendable {
    var version = 1
    var pid = ProcessInfo.processInfo.processIdentifier
    var updatedAt = Date().timeIntervalSince1970
    var lastCheckAt: TimeInterval?
    var lastAutomaticCheckAt: TimeInterval?
    var checkCount = 0
    var busy = false
    var limitGB = 30.0
    var automatic = false
    var loginEnabled = false
    var loginNeedsApproval = false
    var libraryReady: Bool?
    var prefetchReady: Bool?
    var cleanupAllowed = false
    var usedBytes: UInt64?
    var freeBytes: UInt64?
    var totalBytes: UInt64?
    var eligibleBytes: UInt64?
    var message = "Checking storage…"
    var safetyMessage: String?
    var loginMessage: String?
    var lastCommandID: UUID?
}

struct ControlInbox {
    static let commandNotification = Notification.Name("nl.emieljanson.FotoBudget.command")
    static let stateNotification = Notification.Name("nl.emieljanson.FotoBudget.state")
    let root: URL
    var requests: URL { root.appendingPathComponent("requests", isDirectory: true) }
    var stateURL: URL { root.appendingPathComponent("state.json") }

    static var current: ControlInbox {
        ControlInbox(root: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FotoBudget/control", isDirectory: true))
    }

    func prepare() throws {
        for directory in [root, requests] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == getuid() else { throw CocoaError(.fileReadNoPermission) }
            guard chmod(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        }
    }

    func readOwnedData(_ url: URL, maximum: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == getuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= maximum else { return nil }
        var data = Data(count: Int(before.st_size))
        let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        var after = stat()
        guard count == before.st_size, fstat(fd, &after) == 0,
              before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { return nil }
        return data
    }

    func takeCommands(now: TimeInterval = Date().timeIntervalSince1970) -> [ControlRequest] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: requests, includingPropertiesForKeys: nil) else { return [] }
        var commands: [ControlRequest] = []
        for file in files.prefix(64) {
            guard file.pathExtension == "json", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = readOwnedData(file, maximum: 4096) else { continue }
            defer { try? FileManager.default.removeItem(at: file) }
            guard let command = try? JSONDecoder().decode(ControlRequest.self, from: data),
                  command.id == id, command.isValid(now: now) else { continue }
            commands.append(command)
        }
        return commands.sorted { $0.sentAt < $1.sentAt }
    }

    func publish(_ state: AgentState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: [.atomic])
        guard chmod(stateURL.path, 0o600) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    }
}
