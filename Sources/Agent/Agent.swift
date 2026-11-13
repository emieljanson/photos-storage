import AppKit
import CoreServices
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class PhotosStorageAgent: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let workingSpace: UInt64 = 13 * 1024 * 1024 * 1024
    private let tolerance: UInt64 = 8 * 1024 * 1024
    private let chunk: UInt64 = 256 * 1024 * 1024
    private let inbox = ControlInbox.current
    private var state = AgentState()
    private var instanceLock: Int32 = -1
    private var timer: Timer?
    private var busy = false
    private var pendingRequest: (rounds: Int, allowPurge: Bool)?
    private var revision = 0
    private var libraryPath: String?
    private var noProgressLibraryPath: String?
    private var preferencesURL: URL?
    private var preferencesScopeStarted = false
    private var libraryAccessURL: URL?
    private var libraryScopeStarted = false
    private var accessProblem: String?
    private var latestReply: CacheReply?
    private var setupController: SetupWindowController?
    private var openingSettings = false
    private var updates: AppUpdates?
    private var status: String {
        get { state.message }
        set { state.message = newValue; publish() }
    }
    private var limitGB: Double { defaults.double(forKey: "limitGB") }
    private var automatic: Bool { defaults.bool(forKey: "automatic") }
    private var helper: String { Bundle.main.path(forAuxiliaryExecutable: "FotoBudgetCacheHelper") ?? "" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try inbox.prepare()
            instanceLock = open(inbox.root.appendingPathComponent("agent.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard instanceLock >= 0, flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
                NSApp.terminate(nil)
                return
            }
        } catch {
            NSLog("Unable to initialize Photos Storage control storage: %@", String(describing: error))
            NSApp.terminate(nil)
            return
        }
        defaults.register(defaults: ["limitGB": 30.0, "automatic": false, "nativeLastReserveGiB": 13])
        defaults.set(limitGB.isFinite ? min(100_000, max(20, limitGB)) : 30, forKey: "limitGB")
        restorePrefetchAccess()
        restoreLibraryAccess()
        updates = AppUpdates(isIdle: { [weak self] in
            guard let self else { return false }
            return !self.busy && self.pendingRequest == nil && !self.openingSettings && NSApp.modalWindow == nil &&
                self.setupController?.window?.isVisible != true
        }, willRelaunch: { [weak self] in self?.defaults.set(true, forKey: "updateRelaunch") },
           stateDidChange: { [weak self] in self?.publish() })
        if defaults.bool(forKey: "setupCompleted") {
            updates?.start()
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty {
                try? prepareSettingsPane()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(settingsDidQuit(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(receiveCommands(_:)),
            name: ControlInbox.commandNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile(rounds: 1, allowPurge: self?.automatic == true, scheduled: true)
            }
        }
        publish()
        receiveCommands(nil)
        reconcile(rounds: 1, allowPurge: automatic)
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginItem = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let updateRelaunch = defaults.bool(forKey: "updateRelaunch")
        defaults.removeObject(forKey: "updateRelaunch")
        switch launchDestination(arguments: CommandLine.arguments, setupCompleted: defaults.bool(forKey: "setupCompleted"), loginItem: loginItem || updateRelaunch) {
        case .background: break
        case .setup: showSetup()
        case .settings: openSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if defaults.bool(forKey: "setupCompleted") { openSettings() }
        else { showSetup() }
        return false
    }

    private func showSetup() {
        if setupController == nil {
            let model = SetupModel(state: state) { [weak self] action in self?.handleSetup(action) }
            model.automaticUpdates = updates?.enabled ?? true
            setupController = SetupWindowController(model: model)
        }
        setupController?.model.state = state
        setupController?.present()
    }

    @objc private func settingsDidQuit(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.systempreferences", defaults.bool(forKey: "setupCompleted") else { return }
        try? prepareSettingsPane()
    }

    private func prepareSettingsPane() throws {
        guard let source = Bundle.main.builtInPlugInsURL?.appendingPathComponent("PhotosStorage.prefPane") else {
            throw PaneInstallationError.invalidPane
        }
        if FileManager.default.contentsEqual(atPath: source.path, andPath: PaneInstallation.destination.path) { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty {
            throw NSError(domain: "PhotosStorage.Setup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Quit System Settings, then try again to add Photos Storage."])
        }
        try PaneInstallation.install(from: source)
    }

    private func handleSetup(_ action: SetupAction) {
        guard let model = setupController?.model else { return }
        model.error = nil
        switch action {
        case .dismiss: setupController?.close()
        case .start:
            let path = Bundle.main.bundleURL.path
            guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else {
                model.error = "Move Photos Storage to Applications, then open it again."
                return
            }
            do {
                try prepareSettingsPane()
                updates?.setEnabled(model.automaticUpdates)
                model.started = true
                reconcile(rounds: 0, allowPurge: false)
            } catch { model.error = error.localizedDescription }
        case .openPhotos:
            if let libraryPath { NSWorkspace.shared.open(URL(fileURLWithPath: libraryPath)) }
        case .primary:
            switch model.step {
            case .checking: break
            case .library: grantLibraryAccess()
            case .preferences: grantPrefetchAccess()
            case .attention: reconcile(rounds: 0, allowPurge: false)
            case .ready:
                openSettings()
            }
        }
    }

    private func openSettings() {
        guard !openingSettings else { return }
        openingSettings = true
        setupController?.model.openingSettings = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.openingSettings = false
                self.setupController?.model.openingSettings = false
            }
            let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
            if let settings, !settings.isTerminated {
                guard settings.terminate() else {
                    self.showSettingsError("Close System Settings, then try again.")
                    return
                }
                for _ in 0..<50 {
                    if settings.isTerminated { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard settings.isTerminated else {
                    self.showSettingsError("Close System Settings, then try again.")
                    return
                }
            }
            do { try self.prepareSettingsPane() }
            catch {
                self.showSettingsError(error.localizedDescription)
                return
            }
            if NSWorkspace.shared.open(PaneInstallation.destination) {
                self.defaults.set(true, forKey: "setupCompleted")
                self.updates?.start()
                self.setupController?.close()
            } else { self.showSettingsError("System Settings could not be opened. Try again.") }
        }
    }

    private func showSettingsError(_ message: String) {
        showSetup()
        setupController?.model.error = message
    }

    private func publish() {
        state.updatedAt = Date().timeIntervalSince1970
        state.limitGB = limitGB
        state.automatic = automatic
        state.busy = busy
        state.loginEnabled = SMAppService.mainApp.status == .enabled
        state.loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        state.automaticUpdates = updates?.enabled
        state.canCheckForUpdates = updates?.canCheck
        setupController?.model.state = state
        do {
            try inbox.publish(state)
            DistributedNotificationCenter.default().postNotificationName(ControlInbox.stateNotification,
                object: nil, userInfo: nil, deliverImmediately: true)
        } catch {
            NSLog("Unable to publish Photos Storage state: %@", String(describing: error))
        }
        updates?.resumeInstallationIfIdle()
    }

    @objc private func receiveCommands(_ notification: Notification?) {
        for command in inbox.takeCommands() {
            handle(command)
            state.lastCommandID = command.id
            publish()
        }
    }

    private func handle(_ command: ControlRequest) {
        switch command.action {
        case .setLimit:
            guard let value = command.value, let reply = latestReply, reply.cleanupAllowed == true,
                  reply.quotaBytes > 0 else {
                status = "Check Photos access and iCloud optimization before changing the target."
                return
            }
            let capacity = Double(reply.quotaBytes) / 1_000_000_000
            let selected = max(20, value >= capacity - 0.5 ? capacity : min(capacity, value.rounded()))
            defaults.set(selected, forKey: "limitGB")
            revision += 1
            accessProblem = nil
            reconcile(rounds: 4, allowPurge: true, queueIfBusy: true)
        case .setAutomatic:
            guard let enabled = command.enabled else { return }
            guard !enabled || latestReply?.cleanupAllowed == true else {
                status = "Check Photos access and iCloud optimization before enabling monitoring."
                return
            }
            defaults.set(enabled, forKey: "automatic")
            revision += 1
            reconcile(rounds: 1, allowPurge: enabled, queueIfBusy: true)
        case .setLogin:
            if let enabled = command.enabled { setLoginEnabled(enabled) }
        case .refresh: reconcile(rounds: 0, allowPurge: false)
        case .grantLibrary:
            guard !busy else { return }
            grantLibraryAccess()
        case .grantPrefetch:
            guard !busy else { return }
            grantPrefetchAccess()
        case .openPhotos:
            if let libraryPath { NSWorkspace.shared.open(URL(fileURLWithPath: libraryPath)) }
        case .showSetup: showSetup()
        case .checkForUpdates: updates?.check()
        case .setUpdates:
            if let enabled = command.enabled { updates?.setEnabled(enabled) }
        }
    }

    private func updateAccessState(_ run: HelperRun) {
        if run.reply?.ok == true && !run.failed {
            state.libraryReady = true
        } else if run.failureCode == "library_scan_unavailable" {
            state.libraryReady = false
        } else {
            state.libraryReady = nil
        }
        state.prefetchReady = run.reply?.nativeProfileReadable
    }

    private func setLoginEnabled(_ enabled: Bool) {
        state.loginMessage = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                state.loginMessage = "Allow Photos Storage in General › Login Items & Extensions."
            }
        } catch {
            state.loginMessage = "Unable to change login behavior. Check Login Items & Extensions."
        }
        publish()
    }

    private func render(_ reply: CacheReply) {
        latestReply = reply
        state.cleanupAllowed = reply.cleanupAllowed == true
        if state.cleanupAllowed { state.safetyMessage = nil }
        libraryPath = reply.libraryPath
        state.usedBytes = reply.usedBytes
        state.freeBytes = reply.freeBytes
        state.totalBytes = reply.quotaBytes
        state.eligibleBytes = reply.eligibleBytes
        if reply.quotaBytes > 0, limitGB > Double(reply.quotaBytes) / 1_000_000_000 {
            defaults.set(max(20, Double(reply.quotaBytes) / 1_000_000_000), forKey: "limitGB")
            revision += 1
        }
        publish()
    }

    private func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
    private var expectedPreferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.photolibraryd/Data/Library/Preferences/com.apple.photolibraryd.plist")
    }

    private func matchesFile(_ url: URL, expectedURL: URL) -> Bool {
        guard let selected = try? FileManager.default.attributesOfItem(atPath: url.path),
              let expected = try? FileManager.default.attributesOfItem(atPath: expectedURL.path),
              let selectedInode = selected[.systemFileNumber] as? NSNumber,
              let expectedInode = expected[.systemFileNumber] as? NSNumber,
              let selectedDevice = selected[.systemNumber] as? NSNumber,
              let expectedDevice = expected[.systemNumber] as? NSNumber else { return false }
        return selectedInode == expectedInode && selectedDevice == expectedDevice
    }

    private func holdPreferencesAccess(_ url: URL) {
        if preferencesScopeStarted { preferencesURL?.stopAccessingSecurityScopedResource() }
        preferencesURL = url
        preferencesScopeStarted = url.startAccessingSecurityScopedResource()
    }

    private func restorePrefetchAccess() {
        guard let bookmark = defaults.data(forKey: "prefetchAccessBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard matchesFile(url, expectedURL: expectedPreferencesURL) else { return }
            holdPreferencesAccess(url)
            if stale, let renewed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(renewed, forKey: "prefetchAccessBookmark")
            }
        } catch {
            preferencesURL = nil
        }
    }

    @objc private func grantPrefetchAccess() {
        let panel = NSOpenPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.title = "Allow Photos Settings"
        panel.message = "The Photos settings file is selected. Click Allow Settings to continue."
        panel.prompt = "Allow Settings"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        panel.directoryURL = expectedPreferencesURL
        panel.nameFieldStringValue = expectedPreferencesURL.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard matchesFile(url, expectedURL: expectedPreferencesURL) else {
            defaults.set("wrong_file_or_unverifiable", forKey: "prefetchAccessStatus")
            accessProblem = "The selected settings file could not be verified."
            status = accessProblem ?? "Access could not be confirmed."
            return
        }
        holdPreferencesAccess(url)
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: "prefetchAccessBookmark")
            defaults.set("implicit_bookmark_saved", forKey: "prefetchAccessStatus")
            accessProblem = nil
            status = "Access granted. Checking storage…"
            reconcile(rounds: 0, allowPurge: false, queueIfBusy: true)
        } catch {
            let failure = error as NSError
            defaults.set(failure.domain, forKey: "prefetchAccessErrorDomain")
            defaults.set(failure.code, forKey: "prefetchAccessErrorCode")
            defaults.set("bookmark_error", forKey: "prefetchAccessStatus")
            accessProblem = "Access could not be saved. Automatic monitoring remains off."
            status = accessProblem ?? "Access could not be confirmed."
            defaults.set(false, forKey: "automatic")
        }
    }

    private func holdLibraryAccess(_ url: URL) {
        if libraryScopeStarted { libraryAccessURL?.stopAccessingSecurityScopedResource() }
        libraryAccessURL = url
        libraryScopeStarted = url.startAccessingSecurityScopedResource()
    }

    private func restoreLibraryAccess() {
        guard let bookmark = defaults.data(forKey: "libraryAccessBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.isFileURL, url.pathExtension == "photoslibrary" else { return }
            holdLibraryAccess(url)
            if stale, let renewed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(renewed, forKey: "libraryAccessBookmark")
            }
        } catch { libraryAccessURL = nil }
    }

    @objc private func grantLibraryAccess() {
        guard let libraryPath else {
            status = "The System Photo Library has not been found. Check again first."
            return
        }
        let expected = URL(fileURLWithPath: libraryPath)
        let panel = NSOpenPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.title = "Allow Photos Library"
        panel.message = "Your Photos library is selected. Click Allow Library to continue."
        panel.prompt = "Allow Library"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = expected
        panel.nameFieldStringValue = expected.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard matchesFile(url, expectedURL: expected) else {
            state.message = "Choose \(expected.lastPathComponent). Other libraries are not used."
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            holdLibraryAccess(url)
            defaults.set(bookmark, forKey: "libraryAccessBookmark")
            accessProblem = nil
            status = "Access granted. Checking storage…"
            reconcile(rounds: 0, allowPurge: false, queueIfBusy: true)
        } catch {
            status = "Library access could not be saved. Monitoring remains off."
            publish()
            defaults.set(false, forKey: "automatic")
        }
    }


    private func targetBytes(_ reply: CacheReply) -> UInt64 {
        let userTarget = UInt64(limitGB * 1_000_000_000)
        let shortage = workingSpace > reply.freeBytes ? workingSpace - reply.freeBytes : 0
        return min(userTarget, reply.usedBytes > shortage ? reply.usedBytes - shortage : 0)
    }

    private func stopOnError(_ code: String?) {
        pendingRequest = nil
        if code == "helper_timeout" {
            status = automatic
                ? "macOS is not responding yet. Monitoring stays on and will retry in five minutes."
                : "macOS is not responding yet. Try again later or enable automatic monitoring."
            return
        }
        if code == "volume_unavailable" {
            status = "The System Photo Library is unavailable. Photos Storage will check again automatically."
            return
        }
        defaults.set(false, forKey: "automatic")
        switch code {
        case "icloud_photos_disabled":
            state.cleanupAllowed = false
            status = "Cleanup is paused. Enable iCloud Photos in Photos › Settings › iCloud."
            state.safetyMessage=status
        case "storage_optimization_disabled":
            state.cleanupAllowed = false
            status = "Cleanup is paused. Select Optimize Mac Storage in Photos › Settings › iCloud."
            state.safetyMessage=status
        case "icloud_optimization_unverified":
            state.cleanupAllowed = false
            status = "Cleanup is paused. iCloud Photos and Optimize Mac Storage could not be verified."
            state.safetyMessage=status
        case "native_profile_conflict": status = "The prefetch setting was changed outside Photos Storage. Monitoring stopped to preserve that change."
        case "native_profile_unavailable":
            accessProblem = "Prefetch settings could not be read. Allow access before enabling monitoring."
            status = accessProblem ?? ""
        case "native_profile_unconfirmed": status = "The new prefetch setting could not be confirmed. Monitoring is off."
        case "library_scan_unavailable": status = "The library could not be measured. Allow access to the local library and check again."
        case "untested_macos": status = "This macOS version has not been verified. Automatic monitoring is off."
        case "scope_not_verified", "unexpected_quota": status = "Photos storage could not be safely identified. Automatic monitoring is off."
        default: status = "macOS did not confirm cleanup. Automatic monitoring is off. Check Photos and try again."
        }
    }

    private func audit(_ reply: CacheReply) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FotoBudget")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("audit.jsonl")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
            let previous = directory.appendingPathComponent("audit.previous.jsonl")
            if FileManager.default.fileExists(atPath: previous.path) { try? FileManager.default.removeItem(at: previous) }
            try? FileManager.default.moveItem(at: file, to: previous)
        }
        let record: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "limit_gb": limitGB,
            "requested_bytes": reply.requestedBytes, "reported_purged_bytes": reply.reportedPurgedBytes,
            "measured_freed_bytes": reply.measuredFreedBytes, "used_bytes": reply.usedBytes,
            "free_bytes": reply.freeBytes, "ok": reply.ok]
        guard var data = try? JSONSerialization.data(withJSONObject: record) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func reconcile(rounds: Int, allowPurge: Bool, queueIfBusy: Bool = false, scheduled: Bool = false) {
        guard !busy else {
            if queueIfBusy { pendingRequest = (rounds, allowPurge) }
            return
        }
        busy = true
        let path = helper
        let startedRevision = revision
        status = "Checking storage…"
        Task { [weak self] in
            let first = await Task.detached(priority: .utility) { runCacheHelper(path: path, bytes: nil) }.value
            guard let self else { return }
            defer {
                self.busy = false
                self.state.lastCheckAt = Date().timeIntervalSince1970
                self.state.checkCount += 1
                if scheduled { self.state.lastAutomaticCheckAt = self.state.lastCheckAt }
                self.publish()
                if let pending = self.pendingRequest {
                    self.pendingRequest = nil
                    self.reconcile(rounds: pending.rounds, allowPurge: pending.allowPurge)
                }
            }
            if let libraryPath = first.reply?.libraryPath { self.libraryPath = libraryPath }
            self.updateAccessState(first)
            guard let initial = first.reply, initial.ok, !first.failed else {
                self.stopOnError(first.failureCode)
                return
            }
            self.render(initial)
            guard initial.cleanupAllowed==true else {
                self.stopOnError(initial.safetyErrorCode ?? "icloud_optimization_unverified")
                return
            }
            var current = initial
            if allowPurge && self.revision == startedRevision {
                guard initial.nativeProfileReadable == true, let actual = initial.prefetchReserveGiB else {
                    self.stopOnError("native_profile_unavailable")
                    return
                }
                if self.defaults.object(forKey: "pendingNativeReserveGiB") != nil,
                   self.defaults.integer(forKey: "pendingNativeReserveGiB") == actual {
                    self.defaults.set(actual, forKey: "nativeLastReserveGiB")
                    self.defaults.removeObject(forKey: "pendingNativeReserveGiB")
                }
                let expected = self.defaults.integer(forKey: "nativeLastReserveGiB")
                guard actual == expected else {
                    self.stopOnError("native_profile_conflict")
                    return
                }
                let sum = initial.freeBytes.addingReportingOverflow(initial.usedBytes)
                guard !sum.overflow else { self.stopOnError("measurement_unavailable"); return }
                let budgetBytes = UInt64(self.limitGB * 1_000_000_000)
                let reserveBytes = sum.partialValue > budgetBytes ? sum.partialValue - budgetBytes : 0
                let gib = UInt64(1024 * 1024 * 1024)
                let desired = max(13, min(1024, Int(reserveBytes / gib + (reserveBytes % gib == 0 ? 0 : 1))))
                if desired != actual {
                    self.status = "Adjusting prefetch to your storage target…"
                    self.defaults.set(desired, forKey: "pendingNativeReserveGiB")
                    let update = ReserveUpdate(expected: actual, desired: desired)
                    let adjusted = await Task.detached(priority: .utility) { runNativeReserveUpdate(update, helperPath: path) }.value
                    guard adjusted.ok, adjusted.value == desired else {
                        self.stopOnError(adjusted.errorCode ?? "native_profile_unconfirmed")
                        return
                    }
                    self.defaults.set(desired, forKey: "nativeLastReserveGiB")
                    self.defaults.removeObject(forKey: "pendingNativeReserveGiB")
                }
            }
            var reclaimed: UInt64 = 0
            var madeNoProgress = false
            var attemptedPurge = false
            for _ in 0..<rounds {
                guard allowPurge, self.revision == startedRevision else { break }
                let target = self.targetBytes(current)
                if current.usedBytes <= target || current.usedBytes - target <= self.tolerance { break }
                if current.eligibleBytes == 0 { break }
                let amount = min(self.chunk, current.usedBytes - target, current.eligibleBytes)
                self.status = "macOS is freeing eligible local Photos copies…"
                attemptedPurge = true
                let next = await Task.detached(priority: .utility) { runCacheHelper(path: path, bytes: amount) }.value
                guard let result = next.reply, result.ok, !next.failed else {
                    self.stopOnError(next.failureCode)
                    return
                }
                self.audit(result)
                self.render(result)
                reclaimed += result.measuredFreedBytes
                current = result
                if result.measuredFreedBytes < 1024 * 1024 {
                    self.noProgressLibraryPath = result.libraryPath
                    madeNoProgress = true
                    break
                }
                self.noProgressLibraryPath = nil
            }
            let userTarget = UInt64(self.limitGB * 1_000_000_000)
            let result: CacheReply
            // Keep the second measurement near the target and after every cleanup.
            if !attemptedPurge, current.usedBytes <= userTarget,
               userTarget - current.usedBytes >= self.chunk,
               current.freeBytes >= self.workingSpace + self.chunk {
                result = current
            } else {
                let final = await Task.detached(priority: .utility) { runCacheHelper(path: path, bytes: nil) }.value
                guard let refreshed = final.reply, refreshed.ok, !final.failed else {
                    self.stopOnError(final.failureCode)
                    return
                }
                result = refreshed
            }
            self.render(result)
            guard result.cleanupAllowed==true else {
                self.stopOnError(result.safetyErrorCode ?? "icloud_optimization_unverified")
                return
            }
            if let accessProblem = self.accessProblem {
                self.status = accessProblem

                return
            }
            let target = self.targetBytes(result)
            if result.usedBytes > target && result.usedBytes - target > self.tolerance {
                if result.eligibleBytes == 0 || madeNoProgress || self.noProgressLibraryPath == result.libraryPath {
                    if result.usedBytes > UInt64(self.limitGB * 1_000_000_000) {
                        self.status = "macOS cannot free more cache right now. Photos remains above your target."
                    } else if result.freeBytes >= 11 * 1024 * 1024 * 1024 {
                        self.status = "Within your target. macOS cannot free additional cache right now."
                    } else {
                        self.status = "iCloud needs more free disk space. macOS cannot free additional Photos cache right now."
                    }
                } else if self.automatic {
                    self.status = "Monitoring will continue cleanup at the next check."
                } else if result.usedBytes <= UInt64(self.limitGB * 1_000_000_000) {
                    self.status = "More cache may be freed for iCloud. Enable automatic monitoring or change the target."
                } else {
                    self.status = "More cache may be freed. Change the target or enable automatic monitoring."
                }
            } else {
                let freed = reclaimed < 100_000_000
                    ? "\(max(1, reclaimed / 1_000_000)) MB"
                    : self.gb(reclaimed)
                self.status = reclaimed > 0
                    ? "Freed \(freed). Within your storage target."
                    : "Within your target. Free space for iCloud is available."
            }
        }
    }
}
