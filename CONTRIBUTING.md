# Contributing

Open an issue before adding a new utility. Each utility needs a persisted on/off
switch, clear permission guidance and behavior that leaves other apps unchanged.

Use Swift 6 and native SwiftUI controls. Keep UI and documentation in English.
Run `swift test`, `python3 Tests/HomebrewChecks.py` and
`node --test Tests/ReleaseIssuesChecks.cjs` before submitting a pull request.

Test file actions only with disposable files. There is one app identity, so
installing a source build replaces your installed Tac; quit before replacing it.
Never commit signing credentials, exported keys, captures, logs or build output.

For fixes use `Refs #N` rather than closing keywords. Maintainers assign verified
fixes to a release milestone and label them `ready-for-release`. The stable release
workflow closes those issues once all downloads are uploaded.
