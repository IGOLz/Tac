<p align="center"><img src=".github/assets/icon.png" width="128" alt="Tac icon"></p>
<h1 align="center">Tac</h1>
<p align="center">Personal Mac utilities, one switch at a time.</p>

## Install

A local-only Swift 6 / SwiftUI menu bar app. Requires macOS 14 or later.
Builds for this Mac's architecture, signed with the owner's Developer ID.

Run `./scripts/install.sh` to test, build, sign, install into Applications and open Tac.
Enable **Tac** in **System Settings → Privacy & Security → Accessibility**.
The status changes to **Shortcut active** automatically.

Open Tac from its menu bar icon. Closing the window keeps the utility running;
**Quit Tac** stops all shortcuts. **General → Launch at login** is optional.

## Features

**Backspace to Trash:** select files or folders in Finder and press plain Backspace.
Tac adds Command to that event and leaves moving items, permission checks,
confirmations and Undo to Finder. It never deletes files directly or empties Trash.

- Toggle the feature in the window or menu bar; the preference survives restarts.
- Renaming, search fields and other apps keep normal Backspace.
- Existing modified shortcuts, including Command-Backspace, are unchanged.
- Repeated key-down events are ignored after a remapped press.
- Unknown Accessibility focus roles and dialog windows are left unchanged.

**Copy Text from Screen:** press ⌃⇧⌘T to freeze every display and select any
visible text, including text inside images, with on-device Live Text.
Drag to select, ⌘C to copy, Esc or ⌃⇧⌘T again to close.
Requires **Screen Recording** permission for Tac.

## Privacy

No network requests, analytics, third-party dependencies or keyboard recording.
Accessibility is used to inspect Finder focus and modify the Backspace event.
Screen Recording is used only for a one-off capture when you press ⌃⇧⌘T;
captures and recognized text stay in memory and are never saved.
Preferences stay in the local macOS defaults database.

## Development

Open `Package.swift` in Xcode, or run `swift test` / `swift build`.
`./scripts/install.sh` replaces only the installed Tac app and keeps preferences.
The icon source is `.github/assets/make-icon.swift`.

There is one local app identity, `dev.igol.Tac`. No separate Dev app, updater,
notarization pipeline, DMG or public distribution is configured.

To uninstall, quit Tac, disable Launch at login, remove Tac from Accessibility,
then move the app from Applications to Trash.

## License

Private personal software. All rights reserved.
