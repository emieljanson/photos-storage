import AppKit

let application = NSApplication.shared
let controller = PhotosStorageAgent()
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
