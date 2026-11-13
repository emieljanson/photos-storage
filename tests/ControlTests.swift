import Foundation
import Darwin

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let inbox = ControlInbox(root: root)
try inbox.prepare()
let now = Date().timeIntervalSince1970

let paneWire = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let paneRequest = try JSONDecoder().decode(ControlRequest.self, from: paneWire)
expect(paneRequest.action == .setAutomatic && paneRequest.enabled == true && paneRequest.isValid(now: now),
       "The actual Objective-C pane payload must decode as a valid Swift boolean command")

func store(_ action: ControlAction, value: Double? = nil, enabled: Bool? = nil, age: Double = 0) throws -> UUID {
    let id = UUID()
    let request = ControlRequest(version: 1, id: id, sentAt: now - age, action: action, value: value, enabled: enabled)
    try JSONEncoder().encode(request).write(to: inbox.requests.appendingPathComponent(id.uuidString + ".json"))
    return id
}

let valid = try store(.setLimit, value: 30)
let minimum = try store(.setLimit, value: 20)
let setup = try store(.showSetup)
let updates = try store(.setUpdates, enabled: false)
let checkUpdates = try store(.checkForUpdates)
let stop = try store(.setAutomatic, enabled: false)
_ = try store(.setLimit, value: -1)
_ = try store(.setLimit, value: 0)
_ = try store(.setLimit, value: 19.999)
_ = try store(.setAutomatic)
_ = try store(.refresh, value: 1)
_ = try store(.showSetup, enabled: true)
_ = try store(.setUpdates, value: 1)
_ = try store(.checkForUpdates, enabled: true)
_ = try store(.setLimit, value: 30, age: 301)
_ = try store(.setLimit, value: 30, age: -61)
let commands = inbox.takeCommands(now: now)
expect(Set(commands.map(\.id)) == Set([valid, minimum, setup, updates, checkUpdates, stop]), "Only valid, recent, correctly typed commands with targets of at least 20 GB may reach the agent")
expect(inbox.takeCommands(now: now).isEmpty, "A command must not run twice")

let source = root.appendingPathComponent("external.json")
let id = UUID()
let request = ControlRequest(version: 1, id: id, sentAt: now, action: .setLimit, value: 30, enabled: nil)
try JSONEncoder().encode(request).write(to: source)
try FileManager.default.createSymbolicLink(at: inbox.requests.appendingPathComponent(id.uuidString + ".json"), withDestinationURL: source)
expect(inbox.takeCommands(now: now).isEmpty, "A symlink must never supply a cleanup command")
try FileManager.default.removeItem(at: inbox.requests.appendingPathComponent(id.uuidString + ".json"))
try FileManager.default.linkItem(at: source, to: inbox.requests.appendingPathComponent(id.uuidString + ".json"))
expect(inbox.takeCommands(now: now).isEmpty, "A linked file must never supply a cleanup command")

var state = AgentState()
state.limitGB = 25
state.automatic = true
try inbox.publish(state)
let decodedState = try JSONDecoder().decode(AgentState.self, from: inbox.readOwnedData(inbox.stateURL, maximum: 65536)!)
expect(decodedState.limitGB == 25 && decodedState.automatic, "The pane must receive the agent's actual settings")
var info = stat()
expect(lstat(inbox.stateURL.path, &info) == 0 && info.st_mode & 0o777 == 0o600, "Monitoring state must remain private to this account")
print("PASS control commands, stale and invalid input, symlink and hardlink rejection, private state round trip")
