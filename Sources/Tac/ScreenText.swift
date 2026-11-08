import AppKit
import Carbon.HIToolbox
@preconcurrency import ScreenCaptureKit
import SwiftUI
@preconcurrency import VisionKit

enum ScreenTextHotKey {
    static let keyCode = UInt32(kVK_ANSI_T)
    static let modifiers = UInt32(controlKey | shiftKey | cmdKey)
    static let label = "⌃⇧⌘T"

    /// Pixel size of a capture, so text is recognized at the display's native resolution.
    static func pixelSize(points: CGSize, scale: Float) -> (width: Int, height: Int) {
        (Int((points.width * CGFloat(scale)).rounded()), Int((points.height * CGFloat(scale)).rounded()))
    }
}

/// Freezes every display on a global shortcut and makes its text selectable with Live Text.
@MainActor
final class ScreenText: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "screenText"); refresh() }
    }
    @Published private(set) var permitted = CGPreflightScreenCaptureAccess()
    @Published private(set) var failure: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var windows: [ScreenTextWindow] = []
    private var capturing = false
    private var timer: Timer?
    private let analyzer = ImageAnalyzer()
    private let chip = CopiedChip()
    private var previousApp: NSRunningApplication?

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
        if enabled, hotKey == nil {
            let id = EventHotKeyID(signature: OSType(0x5461_6354), id: 1) // "TacT"
            let status = RegisterEventHotKey(ScreenTextHotKey.keyCode, ScreenTextHotKey.modifiers, id,
                                             GetApplicationEventTarget(), 0, &hotKey)
            failure = status == noErr ? nil : "\(ScreenTextHotKey.label) is already used by another app."
        } else if !enabled {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            failure = nil
            dismiss()
        }
    }

    func toggle() {
        if !windows.isEmpty { dismiss(); return }
        guard enabled, !capturing else { return }
        guard CGPreflightScreenCaptureAccess() else { requestPermission(); return }
        guard ImageAnalyzer.isSupported else { failure = "Live Text is not supported on this Mac."; return }
        capturing = true
        Task {
            await show()
            capturing = false
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard !windows.isEmpty else { return }
        let current = windows
        windows = []
        current.forEach { $0.orderOut(nil); $0.close() }
        // Give focus back to the app that was in front before the shortcut.
        if restoreFocus { previousApp?.activate() }
        previousApp = nil
    }

    private func copy(_ text: String, from window: NSWindow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let screen = window.screen ?? NSScreen.main
        dismiss()
        if let screen { chip.show(on: screen) }
    }

    private func show() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Capture every display before showing any overlay, so no overlay appears in a capture.
            var captures: [(NSScreen, CGImage)] = []
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let size = ScreenTextHotKey.pixelSize(points: filter.contentRect.size, scale: filter.pointPixelScale)
                config.width = size.width
                config.height = size.height
                config.showsCursor = false
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                captures.append((screen, image))
            }
            guard !captures.isEmpty else { failure = "No display could be captured."; return }
            failure = nil
            windows = captures.map {
                ScreenTextWindow(screen: $0.0, image: $0.1, analyzer: analyzer,
                                 onClose: { [weak self] in self?.dismiss() },
                                 onCopy: { [weak self] text, window in self?.copy(text, from: window) })
            }
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            windows.forEach { $0.orderFrontRegardless() }
            (windows.first { $0.frame.contains(mouse) } ?? windows[0]).makeKeyAndOrderFront(nil)
        } catch {
            permitted = CGPreflightScreenCaptureAccess()
            failure = "Could not capture the screen: \(error.localizedDescription)"
        }
    }
}

final class ScreenTextWindow: NSWindow {
    private let overlay = ImageAnalysisOverlayView()
    private let hint = NSHostingView(rootView: ChipView(icon: "text.viewfinder", text: "Select text to copy · Esc to close"))
    private let onClose: () -> Void
    private let onCopy: (String, NSWindow) -> Void
    private var dragging = false

    init(screen: NSScreen, image: CGImage, analyzer: ImageAnalyzer,
         onClose: @escaping () -> Void, onCopy: @escaping (String, NSWindow) -> Void) {
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

        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        let imageView = NSImageView(frame: bounds)
        imageView.image = NSImage(cgImage: image, size: screen.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.trackingImageView = imageView
        overlay.preferredInteractionTypes = .textSelection
        container.addSubview(imageView)
        container.addSubview(overlay)

        let size = hint.fittingSize
        hint.frame = NSRect(x: (bounds.width - size.width) / 2, y: screen.visibleFrame.minY - screen.frame.minY + 20,
                            width: size.width, height: size.height)
        hint.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(hint)
        contentView = container
        makeFirstResponder(overlay)

        Task { @MainActor [weak self] in
            let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: .init(.text))
            guard let self else { return }
            self.overlay.analysis = analysis
            if analysis?.hasResults(for: .text) != true {
                self.hint.rootView = ChipView(icon: "text.magnifyingglass", text: "No text found · Esc to close")
            } else {
                self.updateCursor()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self?.hint.animator().alphaValue = 0 }
                }
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { dragging = true }
        super.sendEvent(event)
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .cursorUpdate:
            updateCursor()
        case .leftMouseUp:
            dragging = false
            // Let Live Text finish the selection, then copy it and leave the mode.
            DispatchQueue.main.async { [weak self] in self?.copySelection() }
        default: break
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onClose() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onClose() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "c" {
            if !copySelection() { NSSound.beep() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    private func copySelection() -> Bool {
        let text = overlay.selectedText
        guard !text.isEmpty else { return false }
        onCopy(text, self)
        return true
    }

    /// I-beam over recognized text (and while selecting), arrow elsewhere.
    private func updateCursor() {
        let point = overlay.convert(mouseLocationOutsideOfEventStream, from: nil)
        (dragging || overlay.hasText(at: point) ? NSCursor.iBeam : NSCursor.arrow).set()
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
