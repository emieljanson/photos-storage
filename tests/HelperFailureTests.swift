import Foundation

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

let timeout = runCacheHelper(path: try fixture("timeout", "kill -ALRM $$"), bytes: nil)
expect(timeout.failed, "A timed-out helper must fail without permitting cleanup")
expect(UserDefaults.standard.string(forKey: "lastHelperErrorCode") == "helper_timeout",
       "A helper alarm must be reported as helper_timeout, not an invalid reply")

let exitFailure = runCacheHelper(path: try fixture("exit14", "exit 14"), bytes: nil)
expect(exitFailure.failed, "A nonzero exit must fail")
expect(UserDefaults.standard.string(forKey: "lastHelperErrorCode") != "helper_timeout",
       "Exit code 14 must not be confused with signal 14")

let invalid = runCacheHelper(path: try fixture("invalid", "printf invalid"), bytes: nil)
expect(invalid.reply == nil, "Malformed output must not become a successful reply")
expect(UserDefaults.standard.string(forKey: "lastHelperErrorCode") == "invalid_reply",
       "Malformed output must remain a blocking error")

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

print("HelperFailureTests passed")
