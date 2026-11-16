import AppKit

if CommandLine.arguments.dropFirst().first == "--cloud-file" {
    cloudFileWorkerMain(Array(CommandLine.arguments.dropFirst()))
}

let application = NSApplication.shared
let controller = PhotosStorageAgent()
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
