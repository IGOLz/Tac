import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global key combination: a virtual key code plus Carbon modifier flags.
struct HotKey: Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let screenTextDefault = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | shiftKey | cmdKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    private static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// A message when the combination would get in the way of typing, otherwise nil.
    var validationError: String? {
        let meaningful = modifiers & UInt32(controlKey | optionKey | cmdKey)
        if meaningful == 0 && !Self.functionKeys.contains(Int(keyCode)) {
            return "Add ⌘, ⌃ or ⌥, or use a function key, so the shortcut doesn't get in the way of typing."
        }
        return nil
    }

    /// Modifier symbols in Apple's order, then the key: "⌃⇧⌘T".
    var keys: [String] {
        var result: [String] = []
        if modifiers & UInt32(controlKey) != 0 { result.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { result.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { result.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { result.append("⌘") }
        result.append(Self.keyName(keyCode))
        return result
    }

    var displayString: String { keys.joined() }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The character the key types on the current keyboard layout, uppercased.
    static func keyName(_ keyCode: UInt32) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        let name = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return status == noErr && !name.isEmpty ? name.uppercased() : "Key \(keyCode)"
    }

    // MARK: Persistence

    static func load(_ key: String, from defaults: UserDefaults = .standard) -> HotKey? {
        guard let dict = defaults.dictionary(forKey: key),
              let code = dict["keyCode"] as? Int, let mods = dict["modifiers"] as? Int else { return nil }
        return HotKey(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    func save(_ key: String, to defaults: UserDefaults = .standard) {
        defaults.set(["keyCode": Int(keyCode), "modifiers": Int(modifiers)], forKey: key)
    }
}

/// Click, then press the new combination. Esc cancels. Styled like Flusso's recorder.
struct HotKeyRecorder: View {
    @ObservedObject var screenText: ScreenText
    @State private var recording = false
    @State private var message: String?
    @State private var isError = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if !recording && screenText.shortcut != .screenTextDefault {
                    Button { show(screenText.setShortcut(.screenTextDefault)) } label: {
                        Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Restore \(HotKey.screenTextDefault.displayString)")
                }
                Button { recording ? stop() : start() } label: { label }
                    .buttonStyle(.plain)
                    .help(recording ? "Press the new shortcut, or Esc to cancel" : "Click to change this shortcut")
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : .secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: recording)
        .animation(.snappy, value: message)
        .onDisappear { stop() }
        .onChange(of: screenText.enabled) { _, enabled in if !enabled { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if recording {
                // Red recording indicator, as in the design system's status colours.
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Press Shortcut…").font(.callout.weight(.medium)).foregroundStyle(.tint)
            } else {
                ForEach(Array(screenText.shortcut.keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, key.count > 1 ? 4 : 0)
                        .background(.background, in: .rect(cornerRadius: 5, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.cardStroke) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 140, minHeight: 34)
        .background(recording ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.fill.quaternary),
                    in: .rect(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(recording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear), lineWidth: 1.5)
        }
        .contentShape(.rect)
    }

    private func start() {
        recording = true
        isError = false
        message = "Press keys with ⌘, ⌃ or ⌥. Esc cancels."
        // The current shortcut must reach the recorder instead of opening the overlay.
        screenText.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        if !isError { message = nil }
        screenText.resumeHotKey()
    }

    private func handle(_ event: NSEvent) {
        let candidate = HotKey(event: event)
        if candidate.keyCode == UInt32(kVK_Escape) && candidate.modifiers == 0 {
            show(nil)
            stop()
            return
        }
        if let error = candidate.validationError {
            message = error
            isError = true
            return
        }
        stop()
        show(screenText.setShortcut(candidate))
    }

    private func show(_ error: String?) {
        message = error
        isError = error != nil
    }
}
