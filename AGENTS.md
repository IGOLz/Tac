# Tac

Personal macOS utility for this Mac. Swift 6 and SwiftUI, no package dependencies.
UI and documentation are in English.

- Keep a single signed app identity, dev.igol.Tac. No updater, Dev app or release infrastructure.
- Each utility has a persisted switch. Closing the window must keep enabled utilities running.
- Finder Backspace must never affect editing, other apps or existing modified shortcuts.
- Delegate trashing and Undo to Finder. Never remove files directly.
- Unknown Accessibility context must leave the original key unchanged.
- Run swift test and scripts/install.sh after code changes.
- Interactive deletion tests use only disposable fixtures under ignored build/.
- Keep build artifacts, logs and local configuration out of commits.
