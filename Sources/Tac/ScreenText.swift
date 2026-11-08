import AppKit
import Carbon.HIToolbox
@preconcurrency import ScreenCaptureKit
import Combine
import SwiftUI
import Vision

enum ScreenCapture {
    /// Pixel size of a capture, so text is recognized at the display's native resolution.
    static func pixelSize(points: CGSize, scale: Float) -> (width: Int, height: Int) {
        (Int((points.width * CGFloat(scale)).rounded()), Int((points.height * CGFloat(scale)).rounded()))
    }
}

/// Freezes every display on a global shortcut and makes its text selectable with on-device Vision text recognition.
@MainActor
final class ScreenText: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "screenText"); refresh() }
    }
    @Published private(set) var permitted = CGPreflightScreenCaptureAccess()
    @Published private(set) var failure: String?
    @Published private(set) var shortcut = HotKey.load("screenTextShortcut") ?? .screenTextDefault
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var windows: [ScreenTextWindow] = []
    private var capturing = false
    /// Bumped whenever a pending capture must not open its overlay anymore.
    private var captureGeneration = 0
    private var recordingShortcut = false
    private var timer: Timer?
    private let chip = CopiedChip()
    private var previousApp: NSRunningApplication?
    /// The overlay that should be key once Tac's asynchronous activation completes.
    private weak var keyTarget: NSWindow?

    init() {
        UserDefaults.standard.register(defaults: ["screenText": true])
        enabled = UserDefaults.standard.bool(forKey: "screenText")
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, info in
            MainActor.assumeIsolated {
                guard let info else { return }
                Unmanaged<ScreenText>.fromOpaque(info).takeUnretainedValue().toggle()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }
        // Activation completes asynchronously since macOS 14; a window made key before that stays
        // non-key, and then neither the cursor nor Esc work.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let target = self?.keyTarget, target.isVisible { target.makeKey() }
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.permitted = CGPreflightScreenCaptureAccess() }
        }
    }

    func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func refresh() {
        permitted = CGPreflightScreenCaptureAccess()
        // Vision loads its text models on first use: prepare them now, not when the shortcut is pressed.
        if enabled { TextRecognition.shared.prepare() }
        if enabled, hotKey == nil, !recordingShortcut {
            failure = register(shortcut) ? nil : unavailable(shortcut)
        } else if !enabled {
            unregister()
            failure = nil
            captureGeneration += 1
            dismiss()
        }
    }

    private func unavailable(_ key: HotKey) -> String {
        "\(key.displayString) is already used by another app. Choose another shortcut."
    }

    /// Saves and activates a new shortcut. Returns an error and keeps the old one if it can't be used.
    @discardableResult
    func setShortcut(_ new: HotKey) -> String? {
        if let error = new.validationError { return error }
        if enabled {
            if new != shortcut || hotKey == nil {
                // Claim the new combination before releasing the old one, so a failure keeps it working.
                guard let ref = makeHotKey(new) else { return "\(new.displayString) is already used by another app." }
                unregister()
                hotKey = ref
            }
        }
        shortcut = new
        new.save("screenTextShortcut")
        failure = nil
        return nil
    }

    /// While recording a new shortcut, the current one must reach the recorder instead of opening the overlay.
    func suspendHotKey() {
        recordingShortcut = true
        unregister()
    }

    func resumeHotKey() {
        recordingShortcut = false
        if enabled, hotKey == nil { failure = register(shortcut) ? nil : unavailable(shortcut) }
    }

    private func makeHotKey(_ key: HotKey) -> EventHotKeyRef? {
        let id = EventHotKeyID(signature: OSType(0x5461_6354), id: 1) // "TacT"
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        return ref
    }

    private func register(_ key: HotKey) -> Bool {
        guard let ref = makeHotKey(key) else { return false }
        hotKey = ref
        return true
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func toggle() {
        if !windows.isEmpty { dismiss(); return }
        // A second press while the screen is still being captured cancels it.
        if capturing { captureGeneration += 1; return }
        guard enabled, !recordingShortcut else { return }
        guard CGPreflightScreenCaptureAccess() else { requestPermission(); return }
        capturing = true
        captureGeneration += 1
        let generation = captureGeneration
        Task {
            await show(generation)
            capturing = false
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard !windows.isEmpty else { return }
        let current = windows
        windows = []
        current.forEach { $0.orderOut(nil); $0.close() }
        // Give focus back to the app that was in front before the shortcut.
        if restoreFocus, let previousApp {
            // Since macOS 14 activation is cooperative: the active app hands it over explicitly.
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    private func copy(_ text: String, from window: NSWindow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let screen = window.screen ?? NSScreen.main
        dismiss()
        if let screen { chip.show(on: screen) }
    }

    private func show(_ generation: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Capture every display before showing any overlay, so no overlay appears in a capture.
            var captures: [(NSScreen, CGImage)] = []
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let size = ScreenCapture.pixelSize(points: filter.contentRect.size, scale: filter.pointPixelScale)
                config.width = size.width
                config.height = size.height
                config.showsCursor = false
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                captures.append((screen, image))
            }
            // Disabled, cancelled or recording a shortcut meanwhile: don't take over the screen.
            guard generation == captureGeneration, enabled, !recordingShortcut else { return }
            guard !captures.isEmpty else { failure = "No display could be captured."; return }
            failure = nil
            windows = captures.map {
                ScreenTextWindow(screen: $0.0, image: $0.1,
                                 onClose: { [weak self] in self?.dismiss() },
                                 onCopy: { [weak self] text, window in self?.copy(text, from: window) })
            }
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
            let mouse = NSEvent.mouseLocation
            windows.forEach { $0.orderFrontRegardless() }
            let target = windows.first { $0.frame.contains(mouse) } ?? windows[0]
            keyTarget = target
            NSApp.activate(ignoringOtherApps: true)
            target.makeKeyAndOrderFront(nil)
        } catch {
            permitted = CGPreflightScreenCaptureAccess()
            failure = "Could not capture the screen: \(error.localizedDescription)"
        }
    }
}

final class ScreenTextWindow: NSWindow {
    private let selectionView = SelectionView()
    private let hint = NSHostingView(rootView: ChipView(icon: "text.viewfinder", text: "Reading text…"))
    private let onClose: () -> Void
    private let onCopy: (String, NSWindow) -> Void
    private var layout = TextLayout(lines: [])
    private var anchor: (position: TextPosition, start: CGPoint)?
    /// A press made while text was still being recognized, resumed if the button is still down.
    private var pendingPress: CGPoint?
    private var selection = TextSelection(ranges: [])

    init(screen: NSScreen, image: CGImage, onClose: @escaping () -> Void, onCopy: @escaping (String, NSWindow) -> Void) {
        self.onClose = onClose
        self.onCopy = onCopy
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        backgroundColor = .black

        let size = screen.frame.size
        let bounds = NSRect(origin: .zero, size: size)
        let container = NSView(frame: bounds)
        let imageView = NSImageView(frame: bounds)
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        selectionView.frame = bounds
        selectionView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        container.addSubview(selectionView)

        let hintSize = hint.fittingSize
        hint.frame = NSRect(x: (bounds.width - hintSize.width) / 2, y: screen.visibleFrame.minY - screen.frame.minY + 20,
                            width: hintSize.width, height: hintSize.height)
        hint.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(hint)
        contentView = container
        // Pointer moves arrive even before Tac becomes the active app.
        container.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                 owner: container, userInfo: nil))

        self.image = image
        recognize()
    }

    private var image: CGImage?
    /// Upgrades the fast result once accurate recognition is ready; dropped with the window.
    private var readySubscription: AnyCancellable?

    /// Recognition runs off the main thread. While the accurate models are still being prepared,
    /// the fast ones make the screen selectable right away; the accurate result replaces them
    /// when ready, unless a selection has started.
    private func recognize() {
        guard let image else { return }
        let size = frame.size
        let recognition = TextRecognition.shared
        let accurateReady = recognition.ready
        if !accurateReady { recognition.prepare() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.isVisible, !self.recognized else { return }
            self.setHint(ChipView(icon: "hourglass", text: "Preparing text recognition… The first time can take a minute"))
        }
        Task { @MainActor [weak self] in
            let first = await Self.run(image, size: size, level: accurateReady ? .accurate : .fast)
            guard let self, self.isVisible else { return }
            self.apply(first)
        }
        guard !accurateReady else { return }
        readySubscription = recognition.$state.first { $0 == .ready }.sink { [weak self] _ in
            self?.upgradeToAccurate(size: size)
        }
    }

    private func upgradeToAccurate(size: CGSize) {
        guard isVisible, let image else { return }
        Task { @MainActor [weak self] in
            let accurate = await Self.run(image, size: size, level: .accurate)
            // A press waiting for text resumes on the accurate result; an active selection keeps its layout.
            guard let self, self.isVisible, self.anchor == nil, self.selection.isEmpty, !accurate.isEmpty else { return }
            self.apply(accurate)
        }
    }

    override func close() {
        readySubscription = nil
        image = nil
        super.close()
    }

    private nonisolated static func run(_ image: CGImage, size: CGSize, level: VNRequestTextRecognitionLevel) async -> TextLayout {
        await Task.detached(priority: .userInitiated) {
            (try? TextLayout.recognize(image, size: size, level: level)) ?? TextLayout(lines: [])
        }.value
    }

    private var recognized = false

    private func apply(_ layout: TextLayout) {
        let firstResult = !recognized
        recognized = true
        self.layout = layout
        if let press = pendingPress, NSEvent.pressedMouseButtons & 1 != 0, let position = layout.word(near: press) {
            anchor = (position, press)
        }
        pendingPress = nil
        updateCursor()
        guard firstResult || hint.alphaValue > 0 else { return }
        if layout.isEmpty {
            setHint(ChipView(icon: "text.magnifyingglass", text: "No text found · Esc to close"))
        } else {
            setHint(ChipView(icon: "text.viewfinder", text: "Drag across text to copy · Esc to close"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self?.hint.animator().alphaValue = 0 }
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func setHint(_ chip: ChipView) {
        let center = hint.frame.midX
        hint.rootView = chip
        let size = hint.fittingSize
        hint.frame = NSRect(x: center - size.width / 2, y: hint.frame.minY, width: size.width, height: size.height)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Esc always leaves.
            if event.keyCode == UInt16(kVK_Escape) { onClose(); return }
            super.sendEvent(event)
        case .leftMouseDown:
            mouseDown(at: event.locationInWindow, clicks: event.clickCount)
        case .leftMouseDragged:
            if let anchor { show(layout.selection(from: anchor.position, start: anchor.start, to: event.locationInWindow)) }
            updateCursor()
        case .leftMouseUp:
            anchor = nil
            pendingPress = nil
            if !selection.isEmpty { onCopy(selection.text(in: layout.lines), self) }
        case .mouseMoved, .mouseEntered, .cursorUpdate:
            updateCursor()
        default:
            super.sendEvent(event)
        }
    }

    private func mouseDown(at point: CGPoint, clicks: Int) {
        // A press near a word starts on that word, so the aim doesn't need to be exact.
        guard let position = layout.word(near: point) else {
            anchor = nil
            pendingPress = layout.isEmpty ? point : nil
            show(TextSelection(ranges: []))
            return
        }
        if clicks >= 2 {
            // Double-click copies the word under the pointer.
            anchor = nil
            show(layout.word(position))
        } else {
            anchor = (position, point)
            show(TextSelection(ranges: []))
        }
    }

    private func show(_ new: TextSelection) {
        guard new != selection else { return }
        selection = new
        selectionView.rects = layout.rects(for: new)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "c" {
            if selection.isEmpty { NSSound.beep() } else { onCopy(selection.text(in: layout.lines), self) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// I-beam on or near recognized text, and while selecting; arrow elsewhere.
    private func updateCursor() {
        // Each display has its own window; only the one under the pointer may set the cursor.
        guard isVisible, frame.contains(NSEvent.mouseLocation) else { return }
        // Only the key window may change the cursor.
        if !isKeyWindow, NSApp.isActive { makeKey() }
        let point = mouseLocationOutsideOfEventStream
        let near = layout.word(near: point)
        (anchor != nil || near != nil ? NSCursor.iBeam : NSCursor.arrow).set()
    }
}

/// Draws the selection like selected text: rounded accent-coloured boxes, one per line.
final class SelectionView: NSView {
    var rects: [CGRect] = [] { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        for rect in rects {
            NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -1), xRadius: 3, yRadius: 3).fill()
        }
    }
}

/// Small black capsule matching Flusso's overlay chrome.
struct ChipView: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background {
            Capsule().fill(Color.black)
                .overlay { Capsule().strokeBorder(Color(white: 0.24), lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .padding(12)
        .fixedSize()
    }
}

/// Brief "Text copied" chip at the bottom of a screen, above other windows, never focused.
@MainActor
final class CopiedChip {
    private final class Model: ObservableObject { @Published var visible = false }
    private struct Root: View {
        @ObservedObject var model: Model
        var body: some View {
            ZStack(alignment: .bottom) {
                Color.clear
                if model.visible {
                    ChipView(icon: "checkmark", text: "Text copied")
                        .transition(.scale(scale: 0.55, anchor: .bottom).combined(with: .offset(y: 10)).combined(with: .opacity))
                }
            }.frame(width: 320, height: 90)
        }
    }

    private let model = Model()
    private var generation = 0
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: Root(model: model))
        return panel
    }()

    func show(on screen: NSScreen) {
        generation += 1
        let current = generation
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - 160, y: visible.minY + 8))
        panel.orderFrontRegardless()
        model.visible = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.generation == current else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.model.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}
