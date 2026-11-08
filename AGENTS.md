# Tac

Public macOS utility. Swift 6 and SwiftUI, with Sparkle for signed updates.
UI and documentation are in English.

- Keep one app identity, dev.igol.Tac. Do not create a separate Dev app.
- Public releases are universal, Developer ID signed, notarized and stapled. Follow docs/Releasing.md.
- Sparkle uses the stable GitHub release feed and an EdDSA signing key kept in Keychain.
- Fixes use Refs #N; close ready-for-release issues only after a stable release.
- Each utility has a persisted switch. Closing the window must keep enabled utilities running.
- Finder Backspace must never affect editing, other apps or existing modified shortcuts.
- Delegate trashing and Undo to Finder. Never remove files directly.
- Unknown Accessibility context must leave the original key unchanged.
- Run swift test and scripts/install.sh after code changes.
- Interactive deletion tests use only disposable fixtures under ignored build/.
- Keep build artifacts, logs and local configuration out of commits.
