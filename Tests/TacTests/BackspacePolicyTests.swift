import Testing
import CoreGraphics
@testable import Tac

@Test func finderSelectionOnly() {
    for role in ["AXList", "AXOutline", "AXBrowser", "AXScrollArea", "AXLayoutArea", "AXCell", "AXRow"] {
        #expect(BackspacePolicy.accepts(key: 51, flags: [], finder: true, role: role, editing: false))
    }
    for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXButton", "AXWindow", nil] {
        #expect(!BackspacePolicy.accepts(key: 51, flags: [], finder: true, role: role, editing: false))
    }
    #expect(!BackspacePolicy.accepts(key: 51, flags: [], finder: false, role: "AXList", editing: false))
    #expect(!BackspacePolicy.accepts(key: 51, flags: [], finder: true, role: "AXList", editing: true))
    #expect(!BackspacePolicy.accepts(key: 117, flags: [], finder: true, role: "AXList", editing: false))
}

@Test func preserveExistingShortcuts() {
    for flag: CGEventFlags in [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn] {
        #expect(!BackspacePolicy.accepts(key: 51, flags: flag, finder: true, role: "AXList", editing: false))
    }
    #expect(BackspacePolicy.accepts(key: 51, flags: .maskAlphaShift, finder: true, role: "AXList", editing: false))
}

@Test func screenCaptureUsesNativePixels() {
    #expect(ScreenTextHotKey.pixelSize(points: CGSize(width: 1512, height: 982), scale: 2) == (3024, 1964))
    #expect(ScreenTextHotKey.pixelSize(points: CGSize(width: 1920, height: 1080), scale: 1) == (1920, 1080))
}
