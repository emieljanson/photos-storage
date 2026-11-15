import Foundation
import CryptoKit

// Research only. Round trips use newly generated data, never existing documents.
let keys: Set<URLResourceKey> = [
    .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
    .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemUploadingErrorKey,
    .ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadRequestedKey,
    .ubiquitousItemIsExcludedFromSyncKey, .isRegularFileKey, .isSymbolicLinkKey,
    .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
]

func snapshot(_ url: URL) throws -> [String: Any] {
    let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
    var result: [String: Any] = [:]
    for (key, value) in values.allValues {
        if let error = value as? NSError {
            result[key.rawValue] = ["domain": error.domain, "code": error.code]
        } else if let date = value as? Date {
            result[key.rawValue] = date.timeIntervalSince1970
        } else {
            result[key.rawValue] = value
        }
    }
    return result
}

func emit(_ result: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func waitUntil(_ label: String, timeout: TimeInterval = 120, _ condition: () throws -> Bool) throws {
    let end = Date().addingTimeInterval(timeout)
    repeat {
        if try condition() { return }
        Thread.sleep(forTimeInterval: 1)
    } while Date() < end
    throw NSError(domain: "PhotosStorage.Research", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(label)"])
}

func roundTrip(in root: URL, rounds: Int) throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: root.path) else {
        throw NSError(domain: "PhotosStorage.Research", code: 2)
    }
    let folder = root.appendingPathComponent("Photos Storage Test-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: folder, withIntermediateDirectories: false)
    emit(["event": "created_test_folder", "path": folder.path])
    var generator = SystemRandomNumberGenerator()
    var data = Data(count: 4 * 1024 * 1024)
    data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        for offset in stride(from: 0, to: bytes.count, by: 8) {
            bytes.storeBytes(of: generator.next(), toByteOffset: offset, as: UInt64.self)
        }
    }
    let expectedHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let url = folder.appendingPathComponent("generated-test-data.bin")
    try data.write(to: url, options: .withoutOverwriting)
    emit(["event": "generated", "bytes": data.count, "sha256": expectedHash])
    emit(["event": "fresh_file_guard", "decision": try inspectCloudFile(url).decision.rawValue])
    for round in 1...rounds {
        var stable = 0
        try waitUntil("stable uploaded state") {
            let v = try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
            let ready = v.isUbiquitousItem == true && v.ubiquitousItemIsUploaded == true &&
                v.ubiquitousItemIsUploading == false && v.ubiquitousItemIsDownloading == false &&
                v.ubiquitousItemHasUnresolvedConflicts == false &&
                v.ubiquitousItemDownloadingStatus == .current &&
                v.ubiquitousItemUploadingError == nil && v.ubiquitousItemDownloadingError == nil
            stable = ready ? stable + 1 : 0
            return stable >= 3
        }
        emit(["event": "before_eviction", "round": round, "metadata": try snapshot(url)])
        let reviewed = try inspectCloudFile(url)
        guard reviewed.decision == .ready, let identity = reviewed.identity else {
            throw NSError(domain: "PhotosStorage.Research", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Production safety check refused the test file"])
        }
        let refused = try releaseCloudDownload(url, expectedIdentity: "different-file-version")
        guard refused.error == CloudFileDecision.changed.message, refused.reducedBytes == 0 else {
            throw NSError(domain: "PhotosStorage.Research", code: 5)
        }
        emit(["event": "changed_identity_refused", "round": round])
        let released = try releaseCloudDownload(url, expectedIdentity: identity)
        guard released.error == nil, released.reducedBytes == data.count else {
            throw NSError(domain: "PhotosStorage.Research", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: released.error ?? "Unexpected released size"])
        }
        try waitUntil("cloud-only placeholder") {
            let v = try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
            return v.isUbiquitousItem == true && v.ubiquitousItemIsUploaded == true &&
                v.ubiquitousItemDownloadingStatus == .notDownloaded
        }
        emit(["event": "cloud_only", "round": round, "metadata": try snapshot(url)])
        try manager.startDownloadingUbiquitousItem(at: url)
        try waitUntil("restored download") {
            try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus == .current
        }
        let restored = try Data(contentsOf: url)
        let restoredHash = SHA256.hash(data: restored).map { String(format: "%02x", $0) }.joined()
        guard restoredHash == expectedHash else {
            throw NSError(domain: "PhotosStorage.Research", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Restored data differs"])
        }
        emit(["event": "restored_and_verified", "round": round, "bytes": restored.count,
              "sha256": restoredHash, "metadata": try snapshot(url)])
    }
    let oldIdentity = try cloudFileIdentity(url)
    let modified = data + Data("unsynced edit safety check".utf8)
    try modified.write(to: url)
    let refused = try releaseCloudDownload(url, expectedIdentity: oldIdentity)
    guard refused.error != nil, refused.reducedBytes == 0, try Data(contentsOf: url) == modified else {
        throw NSError(domain: "PhotosStorage.Research", code: 7)
    }
    emit(["event": "changed_content_preserved", "bytes": modified.count])
    emit(["event": "passed", "rounds": rounds, "test_folder": folder.path])
}

func verifyRestoredTest(folder: URL, prefixHash: String) throws {
    guard folder.lastPathComponent.hasPrefix("Photos Storage Test-"), prefixHash.count == 64 else {
        throw NSError(domain: "PhotosStorage.Research", code: 8)
    }
    let url = folder.appendingPathComponent("generated-test-data.bin")
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
    try waitUntil("test download") {
        try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus == .current
    }
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data.prefix(4 * 1024 * 1024)).map { String(format: "%02x", $0) }.joined()
    guard digest == prefixHash, data.suffix(26) == Data("unsynced edit safety check".utf8) else {
        throw NSError(domain: "PhotosStorage.Research", code: 9)
    }
    guard try String(contentsOf: folder.appendingPathComponent("local-only.nosync"), encoding: .utf8) ==
        "A generated local-only safety fixture. Not personal data." else {
        throw NSError(domain: "PhotosStorage.Research", code: 10)
    }
    emit(["event": "ui_round_trip_verified", "bytes": data.count, "prefix_sha256": digest,
          "local_only_fixture_preserved": true])
}

@main
struct CloudStorageProbe {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--cloud-file" {
            cloudFileWorkerMain(Array(CommandLine.arguments.dropFirst()))
        }
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.count == 2 && args[0] == "inspect" {
                emit(["metadata": try snapshot(URL(fileURLWithPath: args[1]))])
            } else if args.count == 2 && args[0] == "round-trip" {
                try roundTrip(in: URL(fileURLWithPath: args[1], isDirectory: true), rounds: 3)
            } else if args.count == 3 && args[0] == "verify-restored-test" {
                try verifyRestoredTest(folder: URL(fileURLWithPath: args[1], isDirectory: true), prefixHash: args[2])
            } else {
                fputs("Usage: cloud-storage-probe inspect PATH | round-trip ICLOUD_FOLDER | verify-restored-test TEST_FOLDER PREFIX_SHA256\n", stderr)
                exit(64)
            }
        } catch {
            let error = error as NSError
            emit(["event": "failed", "domain": error.domain, "code": error.code, "message": error.localizedDescription])
            exit(1)
        }
    }
}
