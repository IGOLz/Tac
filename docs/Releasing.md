# Releasing Tac

Tac has one app identity, `dev.igol.Tac`, with no separate Dev app.

## Signing setup

Use a Developer ID Application identity in the login keychain. The install script
defaults to the owner's identity; `SIGNING_IDENTITY` overrides it. A plain
`scripts/build.sh` uses ad-hoc signing for contributors, with no distribution claims.

Notarization reads ignored `.release.env`. Set either `NOTARY_PROFILE`, or
`NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER`. Keep the API key outside the repo.
No credentials are needed for CI, which builds but never publishes.

Sparkle's private EdDSA key stays in the login keychain, account `ed25519`.
The matching public key is in Info.plist. This is the owner's existing signing
key; never regenerate or replace it casually. Keep its backup in a password
manager. Never export the private key into this repository.

## Stable release

1. Finish and review all concurrent source edits. Run the tests.
2. Increase both CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist.
3. Write release notes. Commit the exact source you intend to release.
4. Run `RELEASE_NOTES=docs/release-notes.md scripts/release.sh`.
5. Inspect the universal app, DMG, ZIP, appcast and checksums in build/release.
6. Push the source, then run `scripts/publish.sh`.

The release script builds both arm64 and x86_64, signs the nested Sparkle helpers
and app, notarizes and staples app and DMG, signs the ZIP update with EdDSA, and
retains previous appcast entries. Packaging uses Finder to save the installer
layout and needs a logged-in desktop session. Move an earlier build/release aside
before rerunning; it is never silently replaced.

The publisher creates a draft against the current commit, uploads all assets,
then publishes it. Stable publication also verifies the downloaded DMG checksum
and updates Casks/tac.rb in IGOLz/homebrew-tap. Retry only the tap step with
`python3 scripts/update-homebrew.py vX.Y.Z` if it fails.

Use `scripts/publish.sh --prerelease` for a prerelease; it does not change the
stable feed or Homebrew. Do not reuse a published version/build number.

## Updates

Sparkle 2 checks GitHub at launch and daily by default. Automatic installation is
off by default. App menu and menu bar expose Check for Updates, and Settings →
Updates exposes both preferences. Users can disable checks.

The feed is https://github.com/IGOLz/Tac/releases/latest/download/appcast.xml.
Only stable releases are offered. Updates are authenticated with EdDSA and the
Developer ID signature. System profiling is disabled.

Before changing updater behavior, test an actual old-to-new signed update in a
disposable macOS user account or VM. Unit tests and signing verification do not
prove that replacement and relaunch work. Do not overwrite the owner's running
app while another agent is testing it.

## Issue completion

Give verified fixes the milestone matching the release tag and label
`ready-for-release`. Stable releases close only those issues after checking all
four assets exist. The workflow supports a manual dry run and idempotent retries.
