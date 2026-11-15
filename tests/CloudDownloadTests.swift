import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
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

let identity = try cloudFileIdentity(local)
try Data("changed after review".utf8).write(to: local)
expect(try cloudFileIdentity(local) != identity, "Changing a file after review invalidates the selection")
let refusedChanged = try releaseCloudDownload(local, expectedIdentity: identity)
expect(refusedChanged.error != nil && refusedChanged.reducedBytes == 0, "A changed file must not be released")
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
print("PASS cloud download guards, local-only preservation, symlinks, library internals, and changed selections")
