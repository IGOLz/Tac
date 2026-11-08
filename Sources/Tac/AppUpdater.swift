import Observation
import Sparkle
import SwiftUI

/// In-app updates with Sparkle. The feed URL and the public signing key are in Info.plist;
/// releases publish a signed appcast next to the ZIP (see docs/Releasing.md).
@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    private var updater: SPUUpdater { controller.updater }

    @ObservationIgnored private var checkedAtLaunch = false
    private(set) var canCheckForUpdates = false

    /// Checks when the app opens and once a day.
    var automaticallyChecks = false {
        didSet {
            if updater.automaticallyChecksForUpdates != automaticallyChecks {
                updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    /// Downloads updates silently and installs them when the app quits, instead of asking first.
    var automaticallyDownloads = false {
        didSet {
            if updater.automaticallyDownloadsUpdates != automaticallyDownloads {
                updater.automaticallyDownloadsUpdates = automaticallyDownloads
            }
        }
    }

    var allowsAutomaticDownloads: Bool { updater.allowsAutomaticUpdates }

    var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private init() {
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        refresh()
    }

    /// Re-reads the preferences, which Sparkle's update window can also change.
    func refresh() {
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
    }

    /// Shows the progress and the result, including "You're up to date".
    func checkForUpdates() { updater.checkForUpdates() }

    /// Called once at launch. Unless updates install automatically, a new version opens
    /// Sparkle's window with the release notes and Install / Remind Me Later / Skip.
    /// With automatic updates, it is downloaded quietly and installed when the app quits.
    func checkAtLaunch() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        guard updater.automaticallyChecksForUpdates else { return }
        Task {
            // Let the main window appear first.
            try? await Task.sleep(for: .seconds(3))
            if !updater.sessionInProgress { updater.checkForUpdatesInBackground() }
        }
    }
}

struct UpdateCommands: Commands {
    let updater: AppUpdater
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

struct UpdateSettingsView: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        PageScroll {
            PageHero(symbol: "arrow.triangle.2.circlepath", color: .green, title: "Updates",
                     description: "Signed updates from GitHub releases.")

            SectionCard(title: "Automatic Updates",
                        footer: "Tac checks for updates at launch and once a day. It asks before installing unless automatic installation is on.") {
                ToggleRow(symbol: "clock.arrow.circlepath", color: .blue, title: "Check for Updates Automatically",
                          isOn: $updater.automaticallyChecks)
                if updater.allowsAutomaticDownloads {
                    RowDivider()
                    ToggleRow(symbol: "arrow.down.circle.fill", color: .green, title: "Download and Install Automatically",
                              subtitle: "Installs when you quit Tac.", isOn: $updater.automaticallyDownloads)
                        .disabled(!updater.automaticallyChecks)
                }
            }

            SectionCard(title: "Version") {
                SettingRow(symbol: "info.circle.fill", color: .gray, title: "Current Version",
                           subtitle: updater.versionDescription) {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .glassButtonStyle()
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .onAppear { updater.refresh() }
    }
}

