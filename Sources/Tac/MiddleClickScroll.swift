import AppKit
import ApplicationServices
import SwiftUI

/// Decides whether a middle click starts autoscroll. Anything with its own action keeps the click.
enum AutoscrollPolicy {
    /// One element from the one under the pointer up to its web area.
    struct Node: Equatable {
        var role: String?
        /// The element offers Press: a link, a control, or something the page handles clicks on.
        var pressable = false
        /// Share of the web area the element covers, from 0 to 1.
        var coverage = 0.0
    }

    /// Middle-clicking these keeps its usual meaning, such as opening a link in a new tab.
    static let interactive: Set<String> = ["AXLink", "AXButton", "AXTextField", "AXTextArea", "AXComboBox",
                                           "AXPopUpButton", "AXMenuButton", "AXCheckBox", "AXRadioButton",
                                           "AXSlider", "AXTab", "AXDisclosureTriangle", "AXIncrementor",
                                           "AXMenuItem", "AXImageMap", "AXVideo", "AXAudio"]

    /// Pages often listen for clicks on a container around everything; that alone isn't an action here.
    static let containerCoverage = 0.5

    /// True only for plain web content, from the element under the pointer outwards.
    static func starts(_ nodes: [Node]) -> Bool {
        for node in nodes {
            guard let role = node.role else { return false }
            if role == "AXWebArea" { return true }
            if interactive.contains(role) { return false }
            if node.pressable && node.coverage < containerCoverage { return false }
        }
        return false
    }

    /// Pixels per second along one axis for a pointer offset in points from the origin, like Windows.
    static func velocity(offset: Double) -> Double {
        let distance = abs(offset) - deadZone
        guard distance > 0 else { return 0 }
        return (offset < 0 ? -1 : 1) * min(distance * 6 + distance * distance * 0.05, 12_000)
    }

    static let deadZone = 12.0
}

@MainActor
final class MiddleClickScroll: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "middleClickScroll"); refresh() }
    }
    @Published private(set) var trusted = false
    @Published private(set) var active = false
    @Published private(set) var failure: String?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var session: Session?
    /// Swallows the release of a click that ended autoscroll.
    private var swallowUp: CGEventType?
    private let indicator = AutoscrollIndicator()

    private struct Session {
        let origin: CGPoint
        var held: Bool
        var left = false
        var last = Date()
        var remainder = CGPoint.zero
        var frame: Timer?
    }

    init() {
        UserDefaults.standard.register(defaults: ["middleClickScroll": true])
        enabled = UserDefaults.standard.bool(forKey: "middleClickScroll")
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
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .leftMouseDown, .leftMouseUp,
                                    .rightMouseDown, .rightMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                let consumed = MainActor.assumeIsolated {
                    guard let info else { return false }
                    return Unmanaged<MiddleClickScroll>.fromOpaque(info).takeUnretainedValue().handle(type, event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            failure = "Could not watch the mouse. Check Accessibility, then quit and reopen Tac."
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
        end()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; active = false; swallowUp = nil
    }

    /// Returns true when the event is consumed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            end()
            if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let middle = event.getIntegerValueField(.mouseEventButtonNumber) == 2
        switch type {
        case .otherMouseDown where middle:
            if session != nil { end(); swallowUp = .otherMouseUp; return true }
            guard enabled, startsAutoscroll(at: event.location) else { return false }
            begin(at: event.location)
            return true
        case .otherMouseDragged where middle:
            return session?.held == true
        case .otherMouseUp where middle:
            if swallowUp == .otherMouseUp { swallowUp = nil; return true }
            guard var session, session.held else { return false }
            // Dragging while holding scrolls until release; a plain click keeps scrolling until the next click.
            if session.left { end() } else { session.held = false; self.session = session }
            return true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard session != nil else { return false }
            end()
            swallowUp = type == .leftMouseDown ? .leftMouseUp : type == .rightMouseDown ? .rightMouseUp : .otherMouseUp
            return true
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard swallowUp == type else { return false }
            swallowUp = nil
            return true
        case .keyDown:
            guard session != nil else { return false }
            end()
            return event.getIntegerValueField(.keyboardEventKeycode) == 53
        default:
            return false
        }
    }

    private func startsAutoscroll(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return false }
        var chain: [(node: AutoscrollPolicy.Node, area: Double)] = []
        for _ in 0..<40 {
            let role = AX.attribute(element, kAXRoleAttribute) as? String
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            let pressable = (actions as? [String] ?? []).contains(kAXPressAction)
            chain.append((AutoscrollPolicy.Node(role: role, pressable: pressable), AX.area(element)))
            if role == nil || role == "AXWebArea" || AutoscrollPolicy.interactive.contains(role!) { break }
            guard let parent = AX.element(AX.attribute(element, kAXParentAttribute)) else { break }
            element = parent
        }
        let page = chain.last?.node.role == "AXWebArea" ? chain.last!.area : 0
        let nodes = chain.map { item in
            var node = item.node
            node.coverage = page > 0 ? item.area / page : 0
            return node
        }
        return AutoscrollPolicy.starts(nodes)
    }

    private func begin(at origin: CGPoint) {
        var session = Session(origin: origin, held: true)
        session.frame = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(session.frame!, forMode: .common)
        self.session = session
        indicator.show(at: origin)
    }

    private func end() {
        session?.frame?.invalidate()
        session = nil
        indicator.hide()
    }

    private func step() {
        guard var session, let pointer = CGEvent(source: nil)?.location else { return }
        let now = Date()
        let elapsed = min(now.timeIntervalSince(session.last), 0.05)
        session.last = now
        let offset = CGPoint(x: pointer.x - session.origin.x, y: pointer.y - session.origin.y)
        if hypot(offset.x, offset.y) > AutoscrollPolicy.deadZone { session.left = true }
        // Moving the pointer below the origin scrolls the page down.
        let dx = -AutoscrollPolicy.velocity(offset: offset.x) * elapsed + session.remainder.x
        let dy = -AutoscrollPolicy.velocity(offset: offset.y) * elapsed + session.remainder.y
        let x = dx.rounded(.towardZero), y = dy.rounded(.towardZero)
        session.remainder = CGPoint(x: dx - x, y: dy - y)
        self.session = session
        guard x != 0 || y != 0,
              let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: Int32(y), wheel2: Int32(x), wheel3: 0) else { return }
        scroll.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // A posted event moves the pointer to its location, so keep the pointer where it is.
        scroll.location = pointer
        scroll.post(tap: .cgSessionEventTap)
    }
}

/// The round marker left at the point where autoscroll started.
@MainActor
private final class AutoscrollIndicator {
    private let size = 34.0
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: AutoscrollMarker())
        return panel
    }()

    func show(at point: CGPoint) {
        // Event coordinates start at the top left of the primary display; AppKit's at the bottom left.
        let height = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrame(NSRect(x: point.x - size / 2, y: height - point.y - size / 2, width: size, height: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

private struct AutoscrollMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
            Image(systemName: "arrow.up.and.down").font(.system(size: 14, weight: .semibold))
        }
        .padding(2)
    }
}
