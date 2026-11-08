import SwiftUI
import ServiceManagement

@main
struct TacApp: App {
    @StateObject private var shortcut = FinderBackspace()
    @StateObject private var screenText = ScreenText()
    var body: some Scene {
        Window("Tac", id: "main") {
            ContentView(shortcut: shortcut, screenText: screenText)
        }.defaultSize(width: 760, height: 520)
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
        Button("Select Text on Screen (\(ScreenTextHotKey.label))") { screenText.toggle() }
            .disabled(!screenText.enabled)
        Button("Open Tac") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Tac") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

private enum DS {
    static let spacing: CGFloat = 24
    static let padding: CGFloat = 24
    static let radius: CGFloat = 14
}

struct ContentView: View {
    @ObservedObject var shortcut: FinderBackspace
    @ObservedObject var screenText: ScreenText
    @State private var page = "Utilities"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("Utilities", systemImage: "switch.2").tag("Utilities")
                Section("Settings") {
                    Label("General", systemImage: "gearshape").tag("General")
                }
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .bottom) {
                Label(shortcut.active ? "Shortcut active" : "Shortcut inactive",
                      systemImage: shortcut.active ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(shortcut.active ? .green : .secondary)
                    .font(.caption).padding()
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacing) {
                    if page == "Utilities" {
                        card {
                            Label("Small changes. Your Mac.", systemImage: "switch.2")
                                .font(.title2.bold())
                            Text("Personal utilities, each with its own switch.").foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Finder").font(.headline)
                            card {
                                Toggle(isOn: $shortcut.enabled) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Backspace to Trash").font(.headline)
                                            Text("Move selected files and folders to the Trash with ⌫.")
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "trash").foregroundStyle(.blue).font(.title2)
                                    }
                                }.toggleStyle(.switch)
                            }
                            Text("Only in Finder. Renaming and text fields keep normal Backspace. Hold-to-repeat is ignored. Use Finder’s Undo to restore an item.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if !shortcut.trusted {
                            card {
                                Label("Allow Accessibility", systemImage: "hand.raised.fill").font(.headline)
                                Text("Tac needs Accessibility to recognize Finder and change the shortcut. Enable Tac in System Settings; it will activate automatically.")
                                Button("Open Accessibility Settings") { shortcut.requestPermission() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if let failure = shortcut.failure { Text(failure).foregroundStyle(.orange) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Screen").font(.headline)
                            card {
                                Toggle(isOn: $screenText.enabled) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Copy Text from Screen").font(.headline)
                                            Text("Press \(ScreenTextHotKey.label) to freeze the screen and select any text, even inside images.")
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "text.viewfinder").foregroundStyle(.blue).font(.title2)
                                    }
                                }.toggleStyle(.switch)
                            }
                            Text("Uses on-device Live Text. Drag to select, ⌘C to copy, Esc or the shortcut again to close.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if screenText.enabled && !screenText.permitted {
                            card {
                                Label("Allow Screen Recording", systemImage: "rectangle.dashed.badge.record").font(.headline)
                                Text("Tac needs Screen Recording to read text on screen. Enable Tac in System Settings, then quit and reopen Tac.")
                                Button("Open Screen Recording Settings") { screenText.requestPermission() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if let failure = screenText.failure { Text(failure).foregroundStyle(.orange) }
                    } else {
                        card {
                            Toggle("Launch at login", isOn: $loginEnabled)
                                .onChange(of: loginEnabled) { _, value in
                                    do {
                                        if value { try SMAppService.mainApp.register() }
                                        else { try SMAppService.mainApp.unregister() }
                                        loginError = nil
                                    } catch { loginError = error.localizedDescription }
                                    loginEnabled = SMAppService.mainApp.status == .enabled
                                }
                            Text("Tac stays available in the menu bar when you close its window.")
                                .foregroundStyle(.secondary)
                            if let loginError { Text(loginError).foregroundStyle(.orange) }
                        }
                        card {
                            Text("Private by default").font(.headline)
                            Text("No network requests, analytics or keyboard recording. Screen text recognition runs on your Mac.")
                        }
                    }
                }.padding(DS.padding).frame(maxWidth: 780)
            }.navigationTitle(page)
                .background(Color(nsColor: .windowBackgroundColor))
                .toolbar { ToolbarItem { Text("Tac").foregroundStyle(.secondary) } }
        }.frame(minWidth: 720, minHeight: 500)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius))
            .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(.separator.opacity(0.4)))
    }
}
