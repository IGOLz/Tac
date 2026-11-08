import SwiftUI
import ServiceManagement

@main
struct TacApp: App {
    @State private var updater = AppUpdater.shared
    @StateObject private var shortcut = FinderBackspace()
    @StateObject private var screenText = ScreenText()
    var body: some Scene {
        Window("Tac", id: "main") {
            ContentView(shortcut: shortcut, screenText: screenText)
                .task { updater.checkAtLaunch() }
        }.defaultSize(width: 760, height: 560)
        .commands { UpdateCommands(updater: updater) }
        MenuBarExtra("Tac", systemImage: "switch.2") {
            MenuContent(shortcut: shortcut, screenText: screenText)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var screenText: ScreenText
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(shortcut.active ? "Finder shortcut active" : "Finder shortcut inactive")
        Toggle("Backspace to Trash", isOn: $shortcut.enabled)
        Toggle("Copy Text from Screen", isOn: $screenText.enabled)
        Button("Select Text on Screen (\(screenText.shortcut.displayString))") { screenText.toggle() }
            .disabled(!screenText.enabled)
        Button("Open Tac") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
            .disabled(!AppUpdater.shared.canCheckForUpdates)
        Divider()
        Button("Quit Tac") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

enum SidebarPage: String, Hashable, CaseIterable, Identifiable {
    case utilities, general, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .utilities: "Utilities"
        case .general: "General"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .utilities: "switch.2"
        case .general: "gearshape.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .utilities: .blue
        case .general: .gray
        case .updates: .green
        }
    }

    static let main: [SidebarPage] = [.utilities]
    static let settings: [SidebarPage] = [.general, .updates]
}

struct ContentView: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var screenText: ScreenText
    @State private var selection: SidebarPage? = .utilities
    /// Back/forward between pages, like System Settings.
    @State private var backStack: [SidebarPage] = []
    @State private var forwardStack: [SidebarPage] = []
    @State private var navigatingHistory = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SidebarPage.main) { SidebarRow(page: $0).tag($0) }
                }
                Section("Settings") {
                    ForEach(SidebarPage.settings) { SidebarRow(page: $0).tag($0) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarStatus(shortcut: shortcut, screenText: screenText) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail(for: selection ?? .utilities)
                .id(selection)
                .transition(.opacity)
                // A fixed toolbar on every page keeps the window chrome from moving.
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Back", systemImage: "chevron.left", action: goBack)
                            .help("Back")
                            .keyboardShortcut("[", modifiers: .command)
                            .disabled(backStack.isEmpty)
                        Button("Forward", systemImage: "chevron.right", action: goForward)
                            .help("Forward")
                            .keyboardShortcut("]", modifiers: .command)
                            .disabled(forwardStack.isEmpty)
                    }
                }
        }
        .animation(.easeOut(duration: 0.15), value: selection)
        .onChange(of: selection) { old, _ in
            if navigatingHistory {
                navigatingHistory = false
            } else if let old {
                backStack.append(old)
                forwardStack.removeAll()
            }
        }
        .background(WindowTitle(title: (selection ?? .utilities).title))
        .frame(minWidth: 720, minHeight: 500)
    }

    private func goBack() {
        guard let page = backStack.popLast() else { return }
        if let selection { forwardStack.append(selection) }
        navigatingHistory = true
        selection = page
    }

    private func goForward() {
        guard let page = forwardStack.popLast() else { return }
        if let selection { backStack.append(selection) }
        navigatingHistory = true
        selection = page
    }

    @ViewBuilder
    private func detail(for page: SidebarPage) -> some View {
        switch page {
        case .utilities: UtilitiesView(shortcut: shortcut, screenText: screenText)
        case .general: GeneralView()
        case .updates: UpdateSettingsView()
        }
    }
}

private struct SidebarRow: View {
    let page: SidebarPage

    var body: some View {
        Label { Text(page.title) } icon: { IconTile(systemName: page.symbol, color: page.color, size: 22) }
    }
}

/// Live status at the bottom of the sidebar.
private struct SidebarStatus: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var screenText: ScreenText

    private var status: (color: Color, title: String, detail: String?) {
        let needsAccessibility = shortcut.enabled && !shortcut.trusted
        let needsScreen = screenText.enabled && !screenText.permitted
        let on = [shortcut.enabled, screenText.enabled].filter { $0 }.count
        if needsAccessibility || needsScreen { return (.orange, "Permissions needed", needsAccessibility ? "Accessibility" : "Screen Recording") }
        if shortcut.failure != nil || screenText.failure != nil { return (.orange, "Check Utilities", nil) }
        if on == 0 { return (.gray, "All utilities off", nil) }
        return (.green, "Ready", on == 1 ? "1 utility on" : "\(on) utilities on")
    }

    var body: some View {
        let status = status
        HStack(spacing: 8) {
            StatusDot(color: status.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(status.title).font(.callout.weight(.medium))
                if let detail = status.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .animation(.snappy, value: status.title)
    }
}

struct UtilitiesView: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var screenText: ScreenText

    var body: some View {
        PageScroll {
            PageHero(symbol: "switch.2", color: .blue, title: "Utilities",
                     description: "Small changes to everyday Mac behavior. Each one has its own switch.")

            if shortcut.enabled && !shortcut.trusted {
                NoticeCard(symbol: "hand.raised.fill", title: "Allow Accessibility",
                           message: "Backspace to Trash needs Accessibility to recognize Finder. It turns on automatically once allowed.") {
                    Button("Open Settings") { shortcut.requestPermission() }.glassProminentButtonStyle()
                }
            }
            if let failure = shortcut.failure {
                NoticeCard(symbol: "exclamationmark.triangle.fill", title: "Backspace to Trash is off", message: failure)
            }

            SectionCard(title: "Finder",
                        footer: "Only in Finder. Renaming and text fields keep normal Backspace. Holding the key doesn't trash the next item. Use Finder's Undo to restore.") {
                ToggleRow(symbol: "trash.fill", color: .blue, title: "Backspace to Trash",
                          subtitle: "Move selected files and folders to the Trash with ⌫.", isOn: $shortcut.enabled)
            }

            if screenText.enabled && !screenText.permitted {
                NoticeCard(symbol: "rectangle.dashed.badge.record", title: "Allow Screen Recording",
                           message: "Copy Text from Screen needs Screen Recording to read the displays. After allowing it, quit and reopen Tac.") {
                    Button("Open Settings") { screenText.requestPermission() }.glassProminentButtonStyle()
                }
            }
            if let failure = screenText.failure {
                NoticeCard(symbol: "exclamationmark.triangle.fill", title: "Copy Text from Screen", message: failure)
            }

            SectionCard(title: "Screen",
                        footer: "Text is recognized on your Mac. Drag across text to copy it, or double-click a word. Only the column you start in is selected. Esc cancels.") {
                ToggleRow(symbol: "text.viewfinder", color: .purple, title: "Copy Text from Screen",
                          subtitle: "Freeze the screen and select any text, even inside images.", isOn: $screenText.enabled)
                RowDivider()
                SettingRow(symbol: "keyboard.fill", color: .gray, title: "Shortcut",
                           subtitle: "Press it anywhere to start selecting text.") {
                    HotKeyRecorder(screenText: screenText)
                }
                .disabled(!screenText.enabled)
                .opacity(screenText.enabled ? 1 : 0.5)
            }
        }
    }
}

struct GeneralView: View {
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        PageScroll {
            PageHero(symbol: "gearshape.fill", color: .gray, title: "General",
                     description: "Startup and privacy.")

            SectionCard(title: "Startup", footer: "Tac stays in the menu bar when you close its window. Quit Tac stops all utilities.") {
                ToggleRow(symbol: "power", color: .green, title: "Launch at Login",
                          subtitle: "Start Tac when you log in to this Mac.", isOn: loginBinding)
            }
            if let loginError {
                NoticeCard(symbol: "exclamationmark.triangle.fill", title: "Launch at login unavailable", message: loginError)
            }

            SectionCard(title: "Privacy") {
                SettingRow(symbol: "hand.raised.fill", color: .blue, title: "Private by default",
                           subtitle: "Only update checks and downloads contact GitHub. No analytics or keyboard recording. Screen text recognition runs on your Mac.")
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding {
            loginEnabled
        } set: { value in
            do {
                if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch { loginError = error.localizedDescription }
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
