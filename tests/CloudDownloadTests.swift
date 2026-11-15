import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func expectRefused(_ message: String, _ action: () throws -> Void) {
    do { try action() } catch { return }
    fatalError(message)
}

let busyFileMessage = "This file is in use. Close it in other apps and choose it again."
let busyFileError = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
for failure in [busyFileError, NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileLocking.rawValue),
                NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileLocking.rawValue,
                        userInfo: [NSUnderlyingErrorKey: busyFileError])] {
    expect(cloudFileFailureMessage(failure) == busyFileMessage,
           "An in-use file must explain how to retry instead of reporting a generic iCloud error")
}
for code in [CocoaError.fileReadNoPermission, .fileWriteNoPermission] {
    expect(cloudFileFailureMessage(NSError(domain: NSCocoaErrorDomain, code: code.rawValue)) ==
           "Access to this file was denied. Choose it again and allow access.",
           "Permission errors must retain their existing guidance")
}
for code in [CocoaError.fileNoSuchFile, .fileReadNoSuchFile] {
    expect(cloudFileFailureMessage(NSError(domain: NSCocoaErrorDomain, code: code.rawValue)) ==
           "This file moved or is no longer available. Choose it again.",
           "Missing files must retain their existing guidance")
}
for failure in [NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue),
                NSError(domain: "OtherDomain", code: Int(EBUSY))] {
    expect(cloudFileFailureMessage(failure) == "macOS could not check this iCloud download. Try again later.",
           "Unknown errors must retain the generic guidance without matching another domain's codes")
}

var ready = CloudFileFacts()
ready.regularFile = true
ready.package = false
ready.ubiquitous = true
ready.uploaded = true
ready.uploading = false
ready.downloading = false
ready.conflicts = false
ready.excluded = false
ready.current = true
ready.downloaded = true
ready.allocatedBytes = 4096
expect(ready.decision == .ready, "A fully uploaded local document can release its download")

for key in ["ubiquitous", "uploaded", "uploading", "downloading", "conflicts", "excluded", "current"] {
    for value in [Optional<Bool>.none, Optional<Bool>.some(key == "uploading" || key == "downloading" || key == "conflicts" || key == "excluded")] {
        var facts = ready
        switch key {
        case "ubiquitous": facts.ubiquitous = value
        case "uploaded": facts.uploaded = value
        case "uploading": facts.uploading = value
        case "downloading": facts.downloading = value
        case "conflicts": facts.conflicts = value
        case "excluded": facts.excluded = value
        default: facts.current = value
        }
        expect(facts.decision != .ready, "Unconfirmed \(key) must block eviction")
    }
}
var facts = ready
facts.hasError = true
expect(facts.decision != .ready, "A failed cloud transfer must block eviction")
for flag in ["uploading", "downloading"] {
    facts = ready
    if flag == "uploading" { facts.uploading = nil } else { facts.downloading = nil }
    expect(facts.decision == .unconfirmed, "An unknown transfer flag must not claim an active transfer")
    if flag == "uploading" { facts.uploading = true } else { facts.downloading = true }
    expect(facts.decision == .syncing, "A confirmed transfer must ask the user to wait")
}
facts = ready
facts.regularFile = false
expect(facts.decision != .ready, "Directories must not recursively release downloads")
facts = ready
facts.package = true
expect(facts.decision != .ready, "Application packages must remain untouched")
facts = ready
facts.downloaded = false
facts.current = false
facts.allocatedBytes = 0
expect(facts.decision == .cloudOnly, "A placeholder needs no cleanup")

let manager = FileManager.default
let folder = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: folder, withIntermediateDirectories: false)
defer { try? manager.removeItem(at: folder) }
let local = folder.appendingPathComponent("local.txt")
try Data("this is the only copy".utf8).write(to: local)
let original = try Data(contentsOf: local)
expect(try inspectCloudFile(local).decision == .notCloud, "An ordinary local file must be rejected")
let refusedLocal = try releaseCloudDownload(local, expectedIdentity: "untrusted")
expect(refusedLocal.error != nil && refusedLocal.reducedBytes == 0, "Local-only files must never release a download")
expect(try Data(contentsOf: local) == original, "Refusing local files must preserve their contents")
var referenceError: NSError?
var validatedReference = false
let refusedReference = PSEvictReviewedUbiquitousItem(local, { resolved in
    validatedReference = true
    expect(resolved.standardizedFileURL == local, "The validator must inspect the bound item's resolved path")
    return false
}, &referenceError)
expect(refusedReference == 0 && referenceError == nil && validatedReference,
       "A refused bound reference must not issue a native eviction request")
expect(try Data(contentsOf: local) == original, "Refusing reference validation must preserve the file")
var visitedMissingReference = false
let missingReference = PSEvictReviewedUbiquitousItem(folder.appendingPathComponent("missing.txt"), { _ in
    visitedMissingReference = true
    return false
}, &referenceError)
expect(missingReference == -1 && referenceError != nil && !visitedMissingReference,
       "An unresolved file reference must fail before validation or eviction")
let hardlink = folder.appendingPathComponent("hardlink.txt")
try manager.linkItem(at: local, to: hardlink)
expect(try inspectCloudFile(hardlink).decision == .notDocument, "Linked files must be classified as unsupported before an access prompt")
try manager.removeItem(at: hardlink)

let symlink = folder.appendingPathComponent("linked.txt")
try manager.createSymbolicLink(at: symlink, withDestinationURL: local)
expect(try inspectCloudFile(symlink).decision == .notDocument, "Symbolic links must be rejected")
let linkedFolder = folder.appendingPathComponent("linked-folder")
try manager.createSymbolicLink(at: linkedFolder, withDestinationURL: folder)
expect(try inspectCloudFile(linkedFolder.appendingPathComponent("local.txt")).decision == .notDocument,
       "A symbolic link in a parent must be rejected too")

let library = folder.appendingPathComponent("Keep.photoslibrary")
try manager.createDirectory(at: library, withIntermediateDirectories: false)
let asset = library.appendingPathComponent("original.jpg")
try Data("sacred".utf8).write(to: asset)
expect(try inspectCloudFile(asset).decision == .notDocument, "Photo library internals must never be candidates")
let package = folder.appendingPathComponent("Keep.app/Contents")
try manager.createDirectory(at: package, withIntermediateDirectories: true)
let packagedFile = package.appendingPathComponent("inside.txt")
try Data("keep package contents".utf8).write(to: packagedFile)
expect(try inspectCloudFile(packagedFile).decision == .notDocument, "Files inside other app packages must be rejected too")
let arbitraryEPUB = folder.appendingPathComponent("Outside Books.epub")
try manager.createDirectory(at: arbitraryEPUB, withIntermediateDirectories: false)
expect(try inspectCloudFile(arbitraryEPUB).decision == .notDocument, "The Books exception must not allow arbitrary EPUB packages")
let bookLocation = booksCloudDocuments.appendingPathComponent("Selected.epub")
expect(isBooksEPUBLocation(bookLocation), "A directly selected Books EPUB has a scoped package exception")
for candidate in [booksCloudDocuments, booksCloudDocuments.appendingPathComponent("nested/Selected.epub"),
                  booksCloudDocuments.appendingPathComponent("Selected.photoslibrary"), arbitraryEPUB] {
    expect(!isBooksEPUBLocation(candidate), "Other libraries, folders and nested paths must not receive the Books exception")
}
var book = ready
book.bookPackage = true
book.regularFile = false
book.package = true
book.dataless = false
book.allocatedBytes = 0
expect(book.preflightDecision == nil && book.decision == .unconfirmed,
       "A fully materialized uploaded book still needs a complete footprint before removal")
book.downloaded = false
book.current = false
book.dataless = true
expect(book.preflightDecision == .cloudOnly, "An offloaded book must finish preflight before any contents are scanned")
for dataless in [Optional<Bool>.none, Optional<Bool>.some(false)] {
    book.dataless = dataless
    expect(book.preflightDecision == .unconfirmed, "A cloud-only package needs the native dataless marker")
}
book = ready
book.bookPackage = true
book.regularFile = false
book.package = true
book.dataless = true
expect(book.preflightDecision == .unconfirmed, "A dataless book must never be scanned as a current local download")

let bookAssets = arbitraryEPUB.appendingPathComponent("OPS")
try manager.createDirectory(at: bookAssets, withIntermediateDirectories: false)
let chapter = bookAssets.appendingPathComponent("chapter.xhtml")
try Data("initial chapter".utf8).write(to: chapter)
let firstBook = try bookPackageContents(arbitraryEPUB)
expect(firstBook.allocatedBytes > 0, "A materialized package counts its local file allocations")
try Data("updated chapter".utf8).write(to: chapter)
expect(try bookPackageContents(arbitraryEPUB).identity != firstBook.identity,
       "Editing a child must invalidate the reviewed package even when its root is unchanged")
let linkedBookAsset = bookAssets.appendingPathComponent("linked.txt")
try manager.createSymbolicLink(at: linkedBookAsset, withDestinationURL: local)
expectRefused("Package inspection must reject symlinks") { _ = try bookPackageContents(arbitraryEPUB) }
try manager.removeItem(at: linkedBookAsset)
try manager.linkItem(at: local, to: linkedBookAsset)
expectRefused("Package inspection must reject hardlinked files") { _ = try bookPackageContents(arbitraryEPUB) }
try manager.removeItem(at: linkedBookAsset)
let nestedLibrary = bookAssets.appendingPathComponent("Keep.photoslibrary")
try manager.createDirectory(at: nestedLibrary, withIntermediateDirectories: false)
expectRefused("Package inspection must reject nested media libraries") { _ = try bookPackageContents(arbitraryEPUB) }
try manager.removeItem(at: nestedLibrary)
let nestedApp = bookAssets.appendingPathComponent("Keep.app")
try manager.createDirectory(at: nestedApp, withIntermediateDirectories: false)
expectRefused("Package inspection must reject nested app packages") { _ = try bookPackageContents(arbitraryEPUB) }
try manager.removeItem(at: nestedApp)

let identity = try cloudFileIdentity(local)
try Data("changed after review".utf8).write(to: local)
expect(try cloudFileIdentity(local) != identity, "Changing a file after review invalidates the selection")
let refusedChanged = try releaseCloudDownload(local, expectedIdentity: identity)
expect(refusedChanged.error == CloudFileDecision.notCloud.message && refusedChanged.reducedBytes == 0,
       "This local fixture is refused before the cloud identity guard; the real cloud probe covers that guard")
expect(try Data(contentsOf: local) == Data("changed after review".utf8), "Changed content must survive a refused request")

let worker = folder.appendingPathComponent("worker.sh")
try Data("#!/bin/sh\nprintf '%s' '{\"error\":\"test result\",\"reducedBytes\":0}'\n".utf8).write(to: worker)
try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
expect(runCloudFileWorker(executable: worker, url: local).error == "test result", "Worker replies must reach the caller")
try Data("#!/bin/sh\nprintf 'not json'\n".utf8).write(to: worker)
expect(runCloudFileWorker(executable: worker, url: local).error != nil, "Malformed worker output must fail closed")
try Data("#!/bin/sh\nprintf '%s' '{\"reducedBytes\":4096}'\nexit 1\n".utf8).write(to: worker)
expect(runCloudFileWorker(executable: worker, url: local).reducedBytes == 0, "A failed worker must never report success")
let childPIDFile = folder.appendingPathComponent("child.pid")
let inheritedOutputScript = "#!/bin/sh\n/bin/sleep 20 &\nprintf '%s' $! > '\(childPIDFile.path)'\nprintf '%s' '{\"error\":\"inherited descriptor\",\"reducedBytes\":0}'\n"
try Data(inheritedOutputScript.utf8).write(to: worker)
let started = Date()
let inherited = runCloudFileWorker(executable: worker, url: local)
let elapsed = Date().timeIntervalSince(started)
if let pid = Int32((try String(contentsOf: childPIDFile, encoding: .utf8))) { kill(pid, SIGTERM) }
expect(inherited.error == "inherited descriptor" && elapsed < 10, "An inherited output descriptor must not hang the app")
try Data("#!/bin/sh\ntrap '' TERM\nexec /bin/sleep 120\n".utf8).write(to: worker)
let timeoutStarted = Date()
let timeout = runCloudFileWorker(executable: worker, url: local)
expect(timeout.error == "iCloud is taking too long to respond. Try again later." &&
       timeout.reducedBytes == 0 && Date().timeIntervalSince(timeoutStarted) < 45,
       "An unresponsive worker must be killed and must never report freed storage")
print("PASS cloud download guards, local-only preservation, linked files, scoped Books packages, and changed selections")
