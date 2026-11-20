import Testing
@testable import Tac

private typealias Node = AutoscrollPolicy.Node

@Test func autoscrollStartsOnlyOnPlainWebContent() {
    #expect(AutoscrollPolicy.starts([Node(role: "AXStaticText"), Node(role: "AXGroup"), Node(role: "AXWebArea")]))
    #expect(AutoscrollPolicy.starts([Node(role: "AXWebArea")]))
    for role in ["AXLink", "AXButton", "AXTextField", "AXTextArea", "AXComboBox", "AXTab", "AXVideo"] {
        #expect(!AutoscrollPolicy.starts([Node(role: "AXStaticText"), Node(role: role), Node(role: "AXWebArea")]))
    }
    // Native views, tab bars and unknown Accessibility context keep the original click.
    #expect(!AutoscrollPolicy.starts([Node(role: "AXScrollArea"), Node(role: "AXWindow")]))
    #expect(!AutoscrollPolicy.starts([Node(role: "AXGroup"), Node(role: nil)]))
    #expect(!AutoscrollPolicy.starts([]))
}

@Test func elementsWithTheirOwnClickKeepIt() {
    // A card or tab the page handles clicks on.
    #expect(!AutoscrollPolicy.starts([Node(role: "AXStaticText"), Node(role: "AXGroup", pressable: true, coverage: 0.05),
                                      Node(role: "AXGroup"), Node(role: "AXWebArea")]))
    // A click listener on a container around the whole page is not an action on the empty area.
    #expect(AutoscrollPolicy.starts([Node(role: "AXGroup"), Node(role: "AXGroup", pressable: true, coverage: 0.9),
                                     Node(role: "AXWebArea")]))
}

@Test func autoscrollSpeedGrowsWithDistance() {
    #expect(AutoscrollPolicy.velocity(offset: 0) == 0)
    #expect(AutoscrollPolicy.velocity(offset: AutoscrollPolicy.deadZone) == 0)
    #expect(AutoscrollPolicy.velocity(offset: 60) > 0)
    #expect(AutoscrollPolicy.velocity(offset: -60) == -AutoscrollPolicy.velocity(offset: 60))
    #expect(AutoscrollPolicy.velocity(offset: 200) > AutoscrollPolicy.velocity(offset: 60) * 3)
    #expect(AutoscrollPolicy.velocity(offset: 5_000) == 12_000)
}
