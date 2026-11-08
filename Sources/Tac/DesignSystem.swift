import AppKit
import SwiftUI

// Personal macOS design system (brain: stack/mac-design-system.md), adapted from Flusso.

// MARK: - Tokens

/// Shared spacing, radii and sizes, so every page has the same rhythm.
enum DS {
    static let pagePadding: CGFloat = 24
    static let pageTop: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let headerSpacing: CGFloat = 8
    static let cardRadius: CGFloat = 14
    static let rowHPadding: CGFloat = 14
    static let rowVPadding: CGFloat = 11
    static let rowIcon: CGFloat = 26
    static let maxContentWidth: CGFloat = 780
}

extension Color {
    /// Page background behind the cards: a soft grey in light mode, the window colour in dark mode.
    static let pageBackground = Color(nsColor: .tacDynamic(light: NSColor(calibratedWhite: 0.962, alpha: 1),
                                                           dark: .windowBackgroundColor))
    /// Card surface: white in light mode, a lifted translucent grey in dark mode.
    static let cardFill = Color(nsColor: .tacDynamic(light: .white, dark: NSColor(calibratedWhite: 1, alpha: 0.055)))
    static let cardStroke = Color(nsColor: .tacDynamic(light: NSColor(calibratedWhite: 0, alpha: 0.075),
                                                       dark: NSColor(calibratedWhite: 1, alpha: 0.075)))
}

extension NSColor {
    static func tacDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}

// MARK: - Surfaces

struct CardSurface: ViewModifier {
    var radius: CGFloat = DS.cardRadius
    var highlighted = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(Color.cardFill)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.045), radius: 2, y: 1)
            }
            .overlay {
                shape.strokeBorder(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.cardStroke),
                                   lineWidth: highlighted ? 1.5 : 1)
            }
            .clipShape(shape)
    }
}

extension View {
    func cardSurface(radius: CGFloat = DS.cardRadius, highlighted: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, highlighted: highlighted))
    }
}

// MARK: - Page scaffolding

/// Scrollable, centred column used by every page.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sectionSpacing) { content }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, DS.pageTop)
                .padding(.bottom, 32)
                .frame(maxWidth: DS.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(OverlayScrollers())
        }
        .background(Color.pageBackground.ignoresSafeArea())
    }
}

/// Overlay scrollers, so a legacy scroll bar never narrows the content and every page keeps its width.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollerStyleView { ScrollerStyleView() }
    func updateNSView(_ view: ScrollerStyleView, context: Context) { view.apply() }

    final class ScrollerStyleView: NSView {
        private var observing = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            guard !observing else { return }
            observing = true
            // AppKit resets the style when the user preference changes.
            NotificationCenter.default.addObserver(self, selector: #selector(preferenceChanged),
                                                   name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        }

        @objc private func preferenceChanged() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
        }
    }
}

/// Large icon, title and description at the top of a page (System Settings style).
struct PageHero: View {
    let symbol: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            IconTile(systemName: symbol, color: color, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .bold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Section title, a card holding the rows, and an optional footer.
struct SectionCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.headerSpacing) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .cardSurface()
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A settings row: coloured icon, title, optional subtitle and a trailing control.
struct SettingRow<Trailing: View>: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { IconTile(systemName: symbol, color: color, size: DS.rowIcon) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, DS.rowHPadding)
        .padding(.vertical, DS.rowVPadding)
        .frame(minHeight: 46)
    }
}

extension SettingRow where Trailing == EmptyView {
    init(symbol: String? = nil, color: Color = .gray, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A row with a small switch on the trailing edge.
struct ToggleRow: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(symbol: symbol, color: color, title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

/// Hairline between rows of a card, inset past the row icon.
struct RowDivider: View {
    var inset: CGFloat = DS.rowHPadding + DS.rowIcon + 12
    var body: some View { Divider().padding(.leading, inset) }
}

/// Tinted call-out card for missing permissions and warnings.
struct NoticeCard<Action: View>: View {
    let symbol: String
    var color: Color = .orange
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(14)
        .background(color.opacity(0.09), in: .rect(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
    }
}

extension NoticeCard where Action == EmptyView {
    init(symbol: String, color: Color = .orange, title: String, message: String) {
        self.init(symbol: symbol, color: color, title: title, message: message) { EmptyView() }
    }
}

/// White SF Symbol on a coloured gradient tile with a fine highlight on top.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .frame(width: size, height: size)
            .background(color.gradient, in: shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
            }
    }
}

/// Status colours: green ready, orange warning, grey off.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: 8, height: 8)
            .background { Circle().fill(color.opacity(0.25)).frame(width: 14, height: 14) }
            .frame(width: 14, height: 14)
    }
}

/// Sets the window title to the page title.
struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView { TitleView() }
    func updateNSView(_ view: TitleView, context: Context) { view.title = title; view.apply() }

    final class TitleView: NSView {
        var title = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            if let window, window.title != title { window.title = title }
        }
    }
}

// MARK: - Liquid Glass and fallback

extension View {
    /// `.glass` on macOS 26, `.bordered` earlier.
    /// Builds with SDKs older than macOS 26 (Swift 6.2) use the fallback only.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// `.glassProminent` on macOS 26, `.borderedProminent` earlier.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
}
