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

These integrations are private macOS interfaces. Capability checks allow
compatible OS updates and stop automatic optimization when an interface changes.
They cannot guarantee how much space macOS will release. The storage target
remains approximate, and Photos needs working space for synchronization.
