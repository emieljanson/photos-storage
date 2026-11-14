import Foundation
import Darwin

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtures) }

func fixture(_ name: String, _ body: String) throws -> String {
    let file = fixtures.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    return file.path
}

let timeout = runCacheProcess(path: try fixture("timeout", "kill -ALRM $$"), arguments: ["--snapshot"], timeout: 2)
expect(timeout.failed, "A timed-out helper must fail without permitting cleanup")
expect(timeout.failureCode == "helper_timeout",
       "A helper alarm must be reported as helper_timeout, not an invalid reply")

let exitFailure = runCacheProcess(path: try fixture("exit14", "exit 14"), arguments: ["--snapshot"], timeout: 2)
expect(exitFailure.failed, "A nonzero exit must fail")
expect(exitFailure.failureCode != "helper_timeout",
       "Exit code 14 must not be confused with signal 14")

let invalid = runCacheProcess(path: try fixture("invalid", "printf invalid"), arguments: ["--snapshot"], timeout: 2)
expect(invalid.reply == nil, "Malformed output must not become a successful reply")
expect(invalid.failureCode == "invalid_reply",
       "Malformed output must remain a blocking error")

let validReply = "{\"ok\":true,\"quota_bytes\":500000000000,\"free_bytes\":100000000000,\"used_bytes\":25000000000,\"eligible_bytes\":0,\"requested_bytes\":0,\"reported_purged_bytes\":0,\"measured_freed_bytes\":0}"
let pidFile = fixtures.appendingPathComponent("writer.pid")
let orphan = try fixture("orphan", "sleep 8 &\nprintf '%s' \"$!\" > '\(pidFile.path)'\nprintf '%s' '\(validReply)'")
let started = Date()
let completed = runCacheProcess(path: orphan, arguments: ["--snapshot"], timeout: 2)
if let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8)) { kill(pid, SIGTERM) }
expect(completed.reply?.ok == true && !completed.failed, "A valid completed helper must return its reply")
expect(Date().timeIntervalSince(started) < 3, "A descendant retaining stdout must not hold a completed check open")

let hung = try fixture("hung", "trap '' TERM ALRM\nexec sleep 20")
let hungStarted = Date()
let bounded = runCacheProcess(path: hung, arguments: ["--snapshot"], timeout: 0.15)
expect(bounded.failed && bounded.failureCode == "helper_timeout", "The parent must bound a helper that ignores its own alarm and SIGTERM")
expect(Date().timeIntervalSince(hungStarted) < 4, "An unresponsive helper must not leave monitoring busy indefinitely")
let missing = runCacheProcess(path: fixtures.appendingPathComponent("missing").path, arguments: [], timeout: 1)
expect(missing.failed && missing.failureCode == "helper_launch_failed", "A missing helper must report launch failure")
let previousLaunchError = UserDefaults.standard.object(forKey: "lastHelperLaunchErrorCode")
defer {
    if let previousLaunchError { UserDefaults.standard.set(previousLaunchError, forKey: "lastHelperLaunchErrorCode") }
    else { UserDefaults.standard.removeObject(forKey: "lastHelperLaunchErrorCode") }
}
let wrapperFailure = runCacheHelper(path: fixtures.appendingPathComponent("missing").path, bytes: nil)
expect(wrapperFailure.failed && wrapperFailure.failureCode == "helper_launch_failed", "The production wrapper must retain launch failures")
expect(wrapperFailure.launchErrorCode != nil && UserDefaults.standard.integer(forKey: "lastHelperLaunchErrorCode") == wrapperFailure.launchErrorCode,
       "The production wrapper must publish its launch-failure diagnostic")

let emptyPreferences = try PropertyListSerialization.data(fromPropertyList: [String: Int](), format: .binary, options: 0)
let malformedPreferences = try PropertyListSerialization.data(fromPropertyList: ["PLPrefetchMinimumFreeDiskGB": "invalid"], format: .binary, options: 0)
expect(nativePrefetchValue(commandOutput: nil, preferencesData: emptyPreferences) == 0,
       "A readable settings file without an override uses Photos' default budget")
expect(nativePrefetchValue(commandOutput: nil, preferencesData: nil) == nil,
       "Missing permission must not be mistaken for a missing override")
expect(nativePrefetchValue(commandOutput: nil, preferencesData: malformedPreferences) == nil,
       "An unreadable override must not be replaced with a default")
expect(nativePrefetchValue(commandOutput: Data("37\n".utf8), preferencesData: nil) == 37,
       "An existing prefetch override must retain its exact value")
expect(nativePrefetchValue(commandOutput: Data("2048\n".utf8), preferencesData: emptyPreferences) == nil,
       "An out-of-range existing override must block changes")

let controller = FailureHarness()
controller.defaults.set(true, forKey: "automatic")
controller.stopOnError(timeout.failureCode)
expect(controller.automatic, "A temporary helper timeout must keep automatic monitoring enabled")
expect(controller.status.contains("five minutes"), "A timeout must explain the scheduled retry")
controller.state.cleanupAllowed = true
controller.stopOnError("icloud_optimization_unverified")
expect(!controller.automatic && !controller.state.cleanupAllowed,
       "An unverified iCloud configuration must still block cleanup and stop automatic monitoring")
controller.stopOnError("helper_timeout")
expect(!controller.automatic, "A timeout must never turn monitoring back on after a safety failure")
for code in ["photos_api_unavailable", "untested_macos"] {
    controller.state.cleanupAllowed = true
    controller.defaults.set(true, forKey: "automatic")
    controller.stopOnError(code)
    expect(!controller.state.cleanupAllowed && !controller.automatic,
           "Losing Photos support must clear previously granted cleanup state and stop monitoring")
    expect(controller.state.safetyMessage == nil,
           "Unsupported Photos must not route users to iCloud settings recovery")
}

print("HelperFailureTests passed")
