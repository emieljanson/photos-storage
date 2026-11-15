import Foundation
import Darwin

enum CloudFileDecision: String, Codable, Sendable {
    case ready, cloudOnly, notDocument, notCloud, unconfirmed, syncing, conflict, changed

    var message: String {
        switch self {
        case .ready: "Ready to remove download"
        case .cloudOnly: "Already stored only in iCloud"
        case .notDocument: "Choose individual documents, outside app libraries"
        case .notCloud: "Not an iCloud document"
        case .unconfirmed: "iCloud upload could not be confirmed"
        case .syncing: "Wait for iCloud to finish syncing"
        case .conflict: "Resolve the iCloud conflict first"
        case .changed: "File changed. Choose it again to review"
        }
    }
}

struct CloudFileFacts {
    var regularFile: Bool?
    var package: Bool?
    var ubiquitous: Bool?
    var uploaded: Bool?
    var uploading: Bool?
    var downloading: Bool?
    var conflicts: Bool?
    var excluded: Bool?
    var current: Bool?
    var downloaded: Bool?
    var allocatedBytes: Int64 = 0
    var hasError = false

    var decision: CloudFileDecision {
        guard regularFile == true, package == false else { return .notDocument }
        guard ubiquitous == true, excluded == false else { return .notCloud }
        guard uploaded == true, !hasError, conflicts != nil else { return .unconfirmed }
        guard conflicts == false else { return .conflict }
        guard uploading == false, downloading == false else { return .syncing }
        if downloaded == false, allocatedBytes == 0 { return .cloudOnly }
        guard current == true, allocatedBytes > 0 else { return .unconfirmed }
        return .ready
    }
}

struct CloudFileSnapshot: Codable, Sendable, Identifiable {
    let url: URL
    let decision: CloudFileDecision
    let allocatedBytes: Int64
    let identity: String?
    var id: URL { url }
}

struct CloudFileResult: Codable, Sendable {
    var snapshot: CloudFileSnapshot?
    var error: String?
    var reducedBytes: Int64 = 0
}

private let cloudFileKeys: Set<URLResourceKey> = [
    .isRegularFileKey, .isPackageKey, .isUbiquitousItemKey,
    .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
    .ubiquitousItemIsDownloadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
    .ubiquitousItemIsExcludedFromSyncKey, .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey,
    .totalFileAllocatedSizeKey
]

func cloudFileIdentity(_ url: URL) throws -> String {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_nlink == 1, info.st_uid == getuid() else { throw CocoaError(.fileReadNoPermission) }
    return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
}

func inspectCloudFile(_ selected: URL) throws -> CloudFileSnapshot {
    let url = URL(fileURLWithPath: selected.path).standardizedFileURL
    let protectedExtensions: Set<String> = ["photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "sparsebundle", "sparseimage"]
    let protectedPath = url.pathComponents.contains { protectedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    guard selected.isFileURL, url.resolvingSymlinksInPath().path == url.path, !protectedPath else {
        return CloudFileSnapshot(url: url, decision: .notDocument, allocatedBytes: 0, identity: nil)
    }
    var parent = url.deletingLastPathComponent()
    while parent.path != "/" {
        if try parent.resourceValues(forKeys: [.isPackageKey]).isPackage == true {
            return CloudFileSnapshot(url: url, decision: .notDocument, allocatedBytes: 0, identity: nil)
        }
        parent.deleteLastPathComponent()
    }
    let values = try url.resourceValues(forKeys: cloudFileKeys)
    var facts = CloudFileFacts()
    facts.regularFile = values.isRegularFile
    facts.package = values.isPackage
    facts.ubiquitous = values.isUbiquitousItem
    facts.uploaded = values.ubiquitousItemIsUploaded
    facts.uploading = values.ubiquitousItemIsUploading
    facts.downloading = values.ubiquitousItemIsDownloading
    facts.conflicts = values.ubiquitousItemHasUnresolvedConflicts
    facts.excluded = values.ubiquitousItemIsExcludedFromSync
    facts.current = values.ubiquitousItemDownloadingStatus.map { $0 == .current }
    facts.downloaded = values.ubiquitousItemDownloadingStatus.map { $0 != .notDownloaded }
    facts.hasError = values.ubiquitousItemUploadingError != nil || values.ubiquitousItemDownloadingError != nil
    facts.allocatedBytes = Int64(values.totalFileAllocatedSize ?? 0)
    let identity = facts.decision == .ready ? try cloudFileIdentity(url) : nil
    return CloudFileSnapshot(url: url, decision: facts.decision, allocatedBytes: facts.allocatedBytes, identity: identity)
}

func releaseCloudDownload(_ url: URL, expectedIdentity: String) throws -> CloudFileResult {
    let before = try inspectCloudFile(url)
    guard before.decision == .ready else { return CloudFileResult(snapshot: before, error: before.decision.message) }
    guard before.identity == expectedIdentity, try cloudFileIdentity(url) == expectedIdentity else {
        return CloudFileResult(snapshot: before, error: CloudFileDecision.changed.message)
    }
    // This official API releases a local download. Never replace it with file deletion.
    try FileManager.default.evictUbiquitousItem(at: url)
    let deadline = Date().addingTimeInterval(8)
    repeat {
        let after = try inspectCloudFile(url)
        if after.decision == .cloudOnly {
            return CloudFileResult(snapshot: after, reducedBytes: before.allocatedBytes)
        }
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    return CloudFileResult(snapshot: try inspectCloudFile(url),
                           error: "Requested. macOS has not confirmed the download was removed. Check again later.")
}

// Same executable, isolated from the agent and its Photos state. Native iCloud calls
// can block; both the child watchdog and parent deadline bound each selected file.
func cloudFileWorkerMain(_ arguments: [String]) -> Never {
    alarm(30)
    let result: CloudFileResult
    do {
        guard arguments.count >= 3, arguments[0] == "--cloud-file",
              arguments[2].hasPrefix("/"), arguments[2].utf8.count <= 4096 else { throw CocoaError(.fileReadInvalidFileName) }
        let url = URL(fileURLWithPath: arguments[2])
        if arguments.count == 3, arguments[1] == "inspect" {
            result = CloudFileResult(snapshot: try inspectCloudFile(url))
        } else if arguments.count == 4, arguments[1] == "release", arguments[3].utf8.count <= 256 {
            result = try releaseCloudDownload(url, expectedIdentity: arguments[3])
        } else { throw CocoaError(.fileReadInvalidFileName) }
    } catch {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain, [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(failure.code) {
            result = CloudFileResult(error: "Access to this file was denied. Choose it again and allow access.")
        } else if failure.domain == NSCocoaErrorDomain, [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(failure.code) {
            result = CloudFileResult(error: "This file moved or is no longer available. Choose it again.")
        } else {
            result = CloudFileResult(error: "macOS could not check this iCloud download. Try again later.")
        }
    }
    if let data = try? JSONEncoder().encode(result) { FileHandle.standardOutput.write(data) }
    exit(0)
}

func runCloudFileWorker(executable: URL, url: URL, identity: String? = nil) -> CloudFileResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["--cloud-file", identity == nil ? "inspect" : "release", url.path] + (identity.map { [$0] } ?? [])
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    defer { try? pipe.fileHandleForReading.close() }
    do { try process.run() }
    catch { return CloudFileResult(error: "The iCloud check could not start. Reopen Photos Storage and try again.") }
    if finished.wait(timeout: .now() + 35) == .timedOut {
        if process.isRunning { process.terminate() }
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
        return CloudFileResult(error: "iCloud is taking too long to respond. Try again later.")
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        return CloudFileResult(error: "The iCloud check stopped before completion. Check again before retrying.")
    }
    let fd = pipe.fileHandleForReading.fileDescriptor
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return CloudFileResult(error: "Unable to read the iCloud result.") }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count > 0 {
            guard data.count + count <= 16_384 else { return CloudFileResult(error: "Unexpected iCloud result.") }
            data.append(contentsOf: buffer.prefix(count))
        } else if count < 0, errno == EINTR { continue }
        else { break }
    }
    return (try? JSONDecoder().decode(CloudFileResult.self, from: data)) ?? CloudFileResult(error: "Unable to confirm the iCloud result.")
}
