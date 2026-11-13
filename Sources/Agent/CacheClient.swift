import Foundation
import Darwin

struct CacheReply: Decodable, Sendable {
    let ok: Bool
    let quotaBytes: UInt64
    let freeBytes: UInt64
    let usedBytes: UInt64
    let eligibleBytes: UInt64
    let requestedBytes: UInt64
    let reportedPurgedBytes: UInt64
    let measuredFreedBytes: UInt64
    let errorCode: String?
    let libraryPath: String?
    var nativeProfileReadable: Bool?
    var prefetchReserveGiB: Int?
    let cleanupAllowed: Bool?
    let safetyErrorCode: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case quotaBytes = "quota_bytes", freeBytes = "free_bytes", usedBytes = "used_bytes"
        case eligibleBytes = "eligible_bytes", requestedBytes = "requested_bytes"
        case reportedPurgedBytes = "reported_purged_bytes", measuredFreedBytes = "measured_freed_bytes"
        case errorCode = "error_code"
        case libraryPath = "library_path"
        case nativeProfileReadable = "native_profile_readable", prefetchReserveGiB = "prefetch_reserve_gib"
        case cleanupAllowed = "cleanup_allowed", safetyErrorCode = "safety_error_code"
    }
}

struct HelperRun: Sendable {
    let reply: CacheReply?
    let failed: Bool
    let failureCode: String?
}

struct ReserveUpdate: Sendable {
    let expected: Int
    let desired: Int
}

func runPreferenceCommand(_ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
        try process.run()
        guard finished.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationReason == .exit, process.terminationStatus == 0, data.count <= 64 else { return nil }
        return data
    } catch { return nil }
}

func nativePreferenceDomain() -> String {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.photolibraryd/Data/Library/Preferences/com.apple.photolibraryd").path
}

func readNativePrefetch() -> Int? {
    guard let data = runPreferenceCommand(["read", nativePreferenceDomain(), "PLPrefetchMinimumFreeDiskGB"]),
          let text = String(data: data, encoding: .utf8),
          let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (0...1024).contains(value) else { return nil }
    return value
}

struct NativeProfileResult: Sendable {
    let ok: Bool
    let value: Int?
    let errorCode: String?
}

func runNativeReserveUpdate(_ update: ReserveUpdate, helperPath: String) -> NativeProfileResult {
    let safety=runCacheHelper(path: helperPath, bytes: nil, safetyOnly: true)
    guard let reply=safety.reply, reply.ok, !safety.failed, reply.cleanupAllowed==true else {
        return NativeProfileResult(ok: false, value: nil,
            errorCode: safety.failureCode ?? safety.reply?.safetyErrorCode ?? "icloud_optimization_unverified")
    }
    guard (13...1024).contains(update.desired), readNativePrefetch() == update.expected else {
        return NativeProfileResult(ok: false, value: nil, errorCode: "native_profile_conflict")
    }
    let written = runPreferenceCommand(["write", nativePreferenceDomain(), "PLPrefetchMinimumFreeDiskGB", "-int", String(update.desired)]) != nil
    let value = readNativePrefetch()
    let confirmed = written && value == update.desired
    return NativeProfileResult(ok: confirmed, value: value, errorCode: confirmed ? nil : "native_profile_unconfirmed")
}

func runCacheHelper(path: String, bytes: UInt64?, safetyOnly: Bool = false) -> HelperRun {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = safetyOnly ? ["--safety"] : bytes.map { ["--purge-bytes", String($0)] } ?? ["--snapshot"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var reply = try? JSONDecoder().decode(CacheReply.self, from: data)
        let timedOut = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGALRM
        let failureCode = timedOut ? "helper_timeout" : reply?.errorCode ?? (reply == nil ? "invalid_reply" : nil)
        UserDefaults.standard.set(process.terminationStatus, forKey: "lastHelperExitStatus")
        UserDefaults.standard.set(failureCode ?? "none", forKey: "lastHelperErrorCode")
        let reserve = readNativePrefetch()
        reply?.nativeProfileReadable = reserve != nil
        reply?.prefetchReserveGiB = reserve
        UserDefaults.standard.set(reserve != nil, forKey: "lastNativeReadPermitted")
        let settingsFile = URL(fileURLWithPath: nativePreferenceDomain() + ".plist")
        do {
            let access = try FileHandle(forReadingFrom: settingsFile)
            try access.close()
            UserDefaults.standard.set(true, forKey: "lastNativeDirectOpenPermitted")
        } catch {
            let failure = error as NSError
            UserDefaults.standard.set(false, forKey: "lastNativeDirectOpenPermitted")
            UserDefaults.standard.set(failure.domain, forKey: "lastNativeDirectOpenErrorDomain")
            UserDefaults.standard.set(failure.code, forKey: "lastNativeDirectOpenErrorCode")
        }
        return HelperRun(reply: reply, failed: process.terminationReason != .exit || process.terminationStatus != 0,
                         failureCode: failureCode)
    } catch {
        UserDefaults.standard.set((error as NSError).code, forKey: "lastHelperLaunchErrorCode")
        return HelperRun(reply: nil, failed: true, failureCode: "helper_launch_failed")
    }
}
