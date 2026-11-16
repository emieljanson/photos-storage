import Foundation
import Darwin
import CryptoKit

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
    var bookPackage = false
    var dataless: Bool?
    var allocatedBytes: Int64 = 0
    var hasError = false

    var preflightDecision: CloudFileDecision? {
        if bookPackage {
            guard regularFile == false, package == true else { return .notDocument }
        } else {
            guard regularFile == true, package == false else { return .notDocument }
        }
        guard ubiquitous == true, excluded == false else { return .notCloud }
        guard uploaded == true, !hasError, conflicts != nil else { return .unconfirmed }
        guard conflicts == false else { return .conflict }
        guard let uploading, let downloading else { return .unconfirmed }
        guard !uploading, !downloading else { return .syncing }
        if downloaded == false {
            guard allocatedBytes == 0, !bookPackage || dataless == true else { return .unconfirmed }
            return .cloudOnly
        }
        guard downloaded == true, current == true, !bookPackage || dataless == false else { return .unconfirmed }
        return nil
    }

    var decision: CloudFileDecision {
        preflightDecision ?? (allocatedBytes > 0 ? .ready : .unconfirmed)
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
    .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isUbiquitousItemKey,
    .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
    .ubiquitousItemIsDownloadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
    .ubiquitousItemIsExcludedFromSyncKey, .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey,
    .totalFileAllocatedSizeKey
]

private let protectedCloudExtensions: Set<String> = ["photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "sparsebundle", "sparseimage"]

let booksCloudDocuments = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Mobile Documents/iCloud~com~apple~iBooks/Documents")

func isBooksEPUBLocation(_ url: URL) -> Bool {
    url.isFileURL && url.pathExtension.lowercased() == "epub" &&
        url.deletingLastPathComponent().path == booksCloudDocuments.path
}

private func cloudItemInfo(_ url: URL) throws -> stat {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
        switch errno {
        case ENOENT, ENOTDIR: throw CocoaError(.fileReadNoSuchFile)
        case EACCES, EPERM: throw CocoaError(.fileReadNoPermission)
        default: throw CocoaError(.fileReadUnknown)
        }
    }
    return info
}

private func cloudStatIdentity(_ info: stat) -> String {
    return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
}

struct BookPackageContents {
    let allocatedBytes: Int64
    let identity: String
}

// Inspect only materialized packages. Enumerating a dataless EPUB downloads it.
func bookPackageContents(_ root: URL) throws -> BookPackageContents {
    let rootInfo = try cloudItemInfo(root)
    guard rootInfo.st_mode & S_IFMT == S_IFDIR, rootInfo.st_uid == getuid(),
          rootInfo.st_flags & UInt32(SF_DATALESS) == 0 else { throw CocoaError(.fileReadNoPermission) }
    var pending = [root]
    var visited: [(url: URL, stamp: String)] = []
    var allocatedBytes: Int64 = 0
    func stamp(_ info: stat) -> String {
        "\(cloudStatIdentity(info)):\(info.st_mode):\(info.st_uid):\(info.st_nlink):\(info.st_flags):\(info.st_blocks)"
    }
    while let url = pending.popLast() {
        guard visited.count < 10_000, url.pathComponents.count - root.pathComponents.count <= 64 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let info = try cloudItemInfo(url)
        guard info.st_uid == getuid(), info.st_dev == rootInfo.st_dev,
              info.st_flags & UInt32(SF_DATALESS) == 0,
              [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT) else { throw CocoaError(.fileReadNoPermission) }
        if url != root {
            guard !protectedCloudExtensions.contains(url.pathExtension.lowercased()),
                  try url.resourceValues(forKeys: [.isPackageKey]).isPackage == false else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            guard info.st_nlink == 1, info.st_blocks >= 0 else { throw CocoaError(.fileReadNoPermission) }
            allocatedBytes += Int64(info.st_blocks) * 512
        case S_IFDIR:
            var enumerationError: Error?
            guard let children = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [],
                options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else { throw CocoaError(.fileReadUnknown) }
            for case let child as URL in children {
                guard visited.count + pending.count < 10_000 else { throw CocoaError(.fileReadTooLarge) }
                pending.append(child)
            }
            if let enumerationError { throw enumerationError }
        default: throw CocoaError(.fileReadNoPermission)
        }
        visited.append((url, stamp(info)))
    }
    for entry in visited {
        guard try stamp(cloudItemInfo(entry.url)) == entry.stamp else { throw CocoaError(.fileReadUnknown) }
    }
    let records = visited.map { [String($0.url.path.dropFirst(root.path.count)), $0.stamp] }
        .sorted { $0[0] < $1[0] }
    let digest = SHA256.hash(data: try JSONEncoder().encode(records)).map { String(format: "%02x", $0) }.joined()
    return BookPackageContents(allocatedBytes: allocatedBytes, identity: "book:\(digest)")
}

func cloudFileIdentity(_ url: URL) throws -> String {
    let info = try cloudItemInfo(url)
    guard info.st_uid == getuid() else { throw CocoaError(.fileReadNoPermission) }
    if info.st_mode & S_IFMT == S_IFDIR, isBooksEPUBLocation(url) {
        let snapshot = try inspectCloudFile(url)
        guard snapshot.decision == .ready, let identity = snapshot.identity else { throw CocoaError(.fileReadNoPermission) }
        return identity
    }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw CocoaError(.fileReadNoPermission) }
    return cloudStatIdentity(info)
}

func inspectCloudFile(_ selected: URL) throws -> CloudFileSnapshot {
    let url = URL(fileURLWithPath: selected.path).standardizedFileURL
    let protectedPath = url.pathComponents.contains { protectedCloudExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
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
    let info = try cloudItemInfo(url)
    let bookLocation = isBooksEPUBLocation(url)
    guard info.st_uid == getuid(), (info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1) ||
            (bookLocation && info.st_mode & S_IFMT == S_IFDIR) else {
        return CloudFileSnapshot(url: url, decision: .notDocument, allocatedBytes: 0, identity: nil)
    }
    let keys = bookLocation && info.st_mode & S_IFMT == S_IFDIR ?
        cloudFileKeys.subtracting([.totalFileAllocatedSizeKey]) : cloudFileKeys
    let values = try url.resourceValues(forKeys: keys)
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
    facts.bookPackage = bookLocation && values.isDirectory == true && values.isPackage == true
    if facts.bookPackage {
        facts.dataless = info.st_flags & UInt32(SF_DATALESS) != 0
        if let decision = facts.preflightDecision {
            return CloudFileSnapshot(url: url, decision: decision, allocatedBytes: 0, identity: nil)
        }
        let contents = try bookPackageContents(url)
        facts.allocatedBytes = contents.allocatedBytes
        return CloudFileSnapshot(url: url, decision: facts.decision, allocatedBytes: facts.allocatedBytes,
                                 identity: facts.decision == .ready ? contents.identity : nil)
    }
    let identity = facts.decision == .ready ? try cloudFileIdentity(url) : nil
    return CloudFileSnapshot(url: url, decision: facts.decision, allocatedBytes: facts.allocatedBytes, identity: identity)
}

func releaseCloudDownload(_ url: URL, expectedIdentity: String) throws -> CloudFileResult {
    let before = try inspectCloudFile(url)
    guard before.decision == .ready else { return CloudFileResult(snapshot: before, error: before.decision.message) }
    guard before.identity == expectedIdentity else {
        return CloudFileResult(snapshot: before, error: CloudFileDecision.changed.message)
    }
    var evictionError: NSError?
    let outcome = PSEvictReviewedUbiquitousItem(url, { boundURL in
        guard let current = try? inspectCloudFile(boundURL) else { return false }
        return current.decision == .ready && current.identity == expectedIdentity
    }, &evictionError)
    if outcome == 0 { return CloudFileResult(snapshot: before, error: CloudFileDecision.changed.message) }
    guard outcome == 1 else { throw evictionError ?? CocoaError(.fileWriteUnknown) }
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

func cloudFileFailureMessage(_ failure: NSError) -> String {
    if (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.fileLocking.rawValue) ||
        (failure.domain == NSPOSIXErrorDomain && failure.code == Int(EBUSY)) {
        return "This file is in use. Close it in other apps and choose it again."
    } else if failure.domain == NSCocoaErrorDomain, [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(failure.code) {
        return "Access to this file was denied. Choose it again and allow access."
    } else if failure.domain == NSCocoaErrorDomain, [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(failure.code) {
        return "This file moved or is no longer available. Choose it again."
    } else {
        return "macOS could not check this iCloud download. Try again later."
    }
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
        result = CloudFileResult(error: cloudFileFailureMessage(error as NSError))
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
