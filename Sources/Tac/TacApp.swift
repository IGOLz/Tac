import SwiftUI
import ServiceManagement

@main
struct TacApp: App {
    @State private var updater = AppUpdater.shared
    @StateObject private var shortcut = FinderBackspace()
    @StateObject private var autoscroll = MiddleClickScroll()
    var body: some Scene {
        Window("Tac", id: "main") {
            ContentView(shortcut: shortcut, autoscroll: autoscroll)
                .task { updater.checkAtLaunch() }
        }.defaultSize(width: 760, height: 560)
        .commands { UpdateCommands(updater: updater) }
        MenuBarExtra("Tac", systemImage: "switch.2") {
            MenuContent(shortcut: shortcut, autoscroll: autoscroll)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var autoscroll: MiddleClickScroll
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(shortcut.active ? "Finder shortcut active" : "Finder shortcut inactive")
        Toggle("Backspace to Trash", isOn: $shortcut.enabled)
        Toggle("Middle-Click Scroll", isOn: $autoscroll.enabled)
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
    @ObservedObject var autoscroll: MiddleClickScroll
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
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarStatus(shortcut: shortcut, autoscroll: autoscroll) }
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
        case .utilities: UtilitiesView(shortcut: shortcut, autoscroll: autoscroll)
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
    @ObservedObject var autoscroll: MiddleClickScroll

    private var status: (color: Color, title: String, detail: String?) {
        let needsAccessibility = (shortcut.enabled && !shortcut.trusted) || (autoscroll.enabled && !autoscroll.trusted)
        let on = [shortcut.enabled, autoscroll.enabled].filter { $0 }.count
        if needsAccessibility { return (.orange, "Permissions needed", "Accessibility") }
        if shortcut.failure != nil || autoscroll.failure != nil { return (.orange, "Check Utilities", nil) }
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
    @ObservedObject var autoscroll: MiddleClickScroll

    var body: some View {
        PageScroll {
            PageHero(symbol: "switch.2", color: .blue, title: "Utilities",
                     description: "Small changes to everyday Mac behavior. Each one has its own switch.")

            if (shortcut.enabled && !shortcut.trusted) || (autoscroll.enabled && !autoscroll.trusted) {
                NoticeCard(symbol: "hand.raised.fill", title: "Allow Accessibility",
                           message: "Backspace to Trash and Middle-Click Scroll need Accessibility to read the item under the pointer or in focus. They turn on automatically once allowed.") {
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

            if let failure = autoscroll.failure {
                NoticeCard(symbol: "exclamationmark.triangle.fill", title: "Middle-Click Scroll is off", message: failure)
            }

            SectionCard(title: "Mouse",
                        footer: "Like Windows: move away from the marker to scroll faster, click or press any key to stop, or hold the wheel, drag and release. Links, tabs, buttons and anything else with its own middle-click keep it; autoscroll starts only on empty page areas.") {
                ToggleRow(symbol: "computermouse.fill", color: .purple, title: "Middle-Click Scroll",
                          subtitle: "Click the mouse wheel on a web page, then move the pointer to scroll.", isOn: $autoscroll.enabled)
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
                           subtitle: "Only update checks and downloads contact GitHub. No analytics, keyboard or mouse recording.")
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
