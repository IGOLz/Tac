import AppKit
import ApplicationServices

enum BackspacePolicy {
    static func accepts(key: Int64, flags: CGEventFlags, finder: Bool, role: String?, editing: Bool) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        return key == 51 && flags.intersection(modifiers).isEmpty && finder && !editing
            && ["AXList", "AXOutline", "AXBrowser", "AXScrollArea", "AXLayoutArea", "AXCell", "AXRow"].contains(role ?? "")
    }
}

@MainActor
final class FinderBackspace: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "finderBackspace"); refresh() }
    }
    @Published private(set) var trusted = false
    @Published private(set) var active = false
    @Published private(set) var failure: String?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var remapped = false

    init() {
        UserDefaults.standard.register(defaults: ["finderBackspace": true])
        enabled = UserDefaults.standard.bool(forKey: "finderBackspace")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        guard enabled && trusted else { stop(); return }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            active = CGEvent.tapIsEnabled(tap: tap)
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                let consumed = MainActor.assumeIsolated {
                    guard let info else { return false }
                    return Unmanaged<FinderBackspace>.fromOpaque(info).takeUnretainedValue().handle(type, event) == nil
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            failure = "Could not enable the shortcut. Check Accessibility, then quit and reopen Tac."
            active = false
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        active = true
        failure = nil
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; active = false; remapped = false
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            remapped = false
            if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return unchanged
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 51 else { return unchanged }
        if type == .keyUp {
            if remapped { event.flags.insert(.maskCommand); remapped = false }
            return unchanged
        }
        // One physical press moves one selection, never the next item through key repeat.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return remapped ? nil : unchanged }
        remapped = false
        guard enabled, let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == "com.apple.finder" else { return unchanged }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let focus = element(attribute(app, kAXFocusedUIElementAttribute)) else { return unchanged }
        let role = attribute(focus, kAXRoleAttribute) as? String
        // Editable text is excluded even when Finder exposes an unexpected role.
        let editing = attribute(focus, kAXSelectedTextRangeAttribute) != nil
        guard BackspacePolicy.accepts(key: 51, flags: event.flags, finder: true, role: role, editing: editing) else { return unchanged }
        if let window = element(attribute(app, kAXFocusedWindowAttribute)) {
            guard attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                  (attribute(window, "AXSheets") as? [AXUIElement] ?? []).isEmpty else { return unchanged }
        }
        // Let Finder handle selection, permissions, Trash, confirmations and Undo.
        event.flags.insert(.maskCommand)
        remapped = true
        return unchanged
    }
}
