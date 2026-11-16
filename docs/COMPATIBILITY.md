# macOS compatibility

Photos Storage 0.4.0 targets Apple silicon Macs running macOS 13 or later.
The app, helper, and embedded Settings pane all declare and compile with that
minimum version. The build checks inspect the actual Mach-O deployment target.
The login feature uses Apple's [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice),
which requires macOS 13.

## Runtime verification

The [compatibility workflow](../.github/workflows/check.yml) builds and tests on
three macOS generations. It then transfers the newest-SDK app to all three
systems, checks the native Photos capabilities, launches the background agent
with optimization off, and loads its actual embedded Settings pane.

| Runtime | Build and isolated safety tests | Same app and Settings pane | Photos capability check |
| --- | --- | --- | --- |
| macOS 15.8.2 | Pass | Pass | Pass |
| macOS 26.7.2 | Pass | Pass | Pass |
| macOS 27.0.1 | Pass | Pass | Pass |

[Recorded CI run](https://github.com/emieljanson/photos-storage/actions/runs/43579317416)
on November 14, 2026. A read-only capability check also passes locally on
macOS 27.2. macOS 13 and 14 are deployment targets without a runtime test result.
These checks do not verify end-to-end iCloud synchronization or cleanup on
each OS. CI does not request cleanup or grant access to a personal library.

## Checks on every installation

The helper checks the actual Photos and CacheDelete functions instead of
allowing one exact macOS build. Before interpreting the library's optimization
mode, it verifies that Photos itself describes mode 0 as `optimize`, using the
expected method signature and return type. Missing or changed functions stop
the operation.

Each operation still requires confirmed iCloud Photos, Optimize Mac Storage,
and a stable System Photo Library. Cleanup is scoped to Apple's Photos cache
service, limited to 256 MiB per request, and rechecks safety immediately before
calling it. The app never selects media files for deletion or calls an asset
deletion API. An unreadable settings file remains an access failure; an absent
prefetch override in a readable settings file uses Photos' default behavior.

The storage **mode** is checked separately from that prefetch budget. If
`Library.CPL.PrefetchMode` is absent in a valid per-library settings file, the
helper asks Photos for its effective mode through a fresh, library-bound
`PLAssetsdClient.cloudClient.getCPLSettings` read. Setup offers Photos Full
Access only for this case. Missing permission, unavailable replies, changed
method signatures, contradictory getters, and unknown modes never permit
cleanup. The existing iCloud logs and markers must still pass, and the library
settings are reread after the request to reject a concurrent settings change.

The native reply's `isICPLEnabled` flag is used with `prefetchMode` and
`isKeepOriginalsEnabled`. `isCloudPhotoLibraryEnabled` depends on additional
library context and returned false in a real authorized client even when
`isICPLEnabled` was true. `hasPersistedPrefetchMode` is not used on the detached
reply. No absent mode is interpreted as an implicit default.

On macOS 27.2, a read-only live test returned mode 0 with iCloud enabled from
both the authorized app and its child helper. Without Photos authorization,
the service refused the read with Photos error 41011. Isolated tests execute
the OS's real settings getters for optimize, originals, unknown modes, and
enabled/disabled iCloud using encoded daemon-reply fixtures. They do not change
a real library's mode or perform cleanup. The new fallback has not yet been
live-tested on other macOS versions.

A separate macOS 27.2 test used a fresh app without file bookmarks, before and
after granting Photos Full Access and again from its child helper. Library
measurement worked in both states. Reading the Photos daemon preferences,
opening that file for writing, and the production budget read stayed denied
with `EPERM`. Photos authorization therefore does not replace settings-file
access for the current budget implementation. The real budget was not changed.
Setup still requires the Photos Settings check to pass. If it stays pending,
choose **Allow Photos Settings…** in setup and allow the selected settings file,
even if Photos Full Access has already been granted.

These integrations are private macOS interfaces. Capability checks allow
compatible OS updates and stop automatic optimization when an interface changes.
They cannot guarantee how much space macOS will release. The storage target
remains approximate, and Photos needs working space for synchronization.
