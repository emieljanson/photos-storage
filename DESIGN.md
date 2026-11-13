# System Settings interface

The pane follows the grouped rows used in AirDrop & Continuity and Battery
settings. Keep the main view to local Photos usage, a storage target, and
automatic optimization. Do not bring back the full-disk graph or slider:
they made a Photos setting look like a disk-management tool.

- Use native AppKit pop-up buttons, mini switches, text fields, and sheets.
- Offer common targets in a flat menu and retain a custom current value.
  Offer 20, 30, 50, 75, 100, 150, and 200 GB. **Custom…** keeps the whole-number
  range from 20 GB to disk capacity. Targets below 20 GB are rejected by both
  the pane and background agent; older saved targets are raised to 20 GB.
- Put login behavior, check details, and manual actions in **Options…**.
- Show permission or safety recovery only when it is needed. Put **Around**
  before the target menu to convey approximation; do not repeat it in menu
  items or add a separate caveat below the form.
- Use system fonts and semantic text colors, compact rows, thin separators,
  and backgrounds that adapt to light and dark appearance.
- Keep background monitoring independent of pane and sheet lifetimes.

## First launch

The disk image contains one app and an Applications shortcut. The app bundles
the settings pane and installs it for the current user when they continue.
Keep setup to a welcome screen, the permissions that are actually missing,
and a direct **Open System Settings** action. That action opens the installed
preference-pane bundle; the custom URL scheme opened General during testing
on the verified macOS build.

On build 26B123, navigating away from an already loaded third-party pane and
back can leave its content blank. This also reproduced with macFUSE. The
app therefore requests a normal termination of System Settings, waits for it
to exit, and opens the installed pane in a fresh Settings window. It never
force-quits Settings. A refused or delayed quit leaves a clear retry message.
The ready screen says that System Settings reopens.

Use native SwiftUI buttons, SF Symbols, and semantic colors. Explain each
permission before its file picker appears. Do not show an introduction on
later launches or when starting at login. Permission and iCloud safety checks
must both succeed before displaying the ready screen.

## Apple guidance

- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
  — minimize the settings people must manage.
- [Pop-up buttons](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons)
  — a compact selection among mutually exclusive choices.
- [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles)
  — mini switches in macOS grouped forms.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
  — alignment, grouping, and consistent spacing.
