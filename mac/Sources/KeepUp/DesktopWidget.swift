import AppKit
import Combine
import SwiftUI

/// The desktop widget: a small borderless glass panel that sits on the
/// desktop itself (above the wallpaper and icons, below every normal
/// window), on all Spaces. Drag it anywhere; the position is remembered.
///
/// A real WidgetKit widget would need a paid Apple Developer account to
/// show up at all, so this is a plain window pinned at desktop level,
/// which needs nothing beyond the ad-hoc signed app.
@MainActor
final class DesktopWidget {
    static let shared = DesktopWidget()

    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    static let width: CGFloat = 300

    var isVisible: Bool { panel?.isVisible ?? false }

    func refreshVisibility() {
        if UserDefaults.standard.bool(forKey: Pref.widgetOn) { show() } else { hide() }
    }

    func show() {
        if panel == nil { build() }
        panel?.orderFront(nil)
        resize()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let panel = WidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let host = FirstMouseHostingView(rootView: WidgetView())
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host

        if !panel.setFrameUsingName("KeepUpWidget"), let screen = NSScreen.main {
            // First run: top-right corner of the main screen.
            let vis = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vis.maxX - Self.width - 24, y: vis.maxY - 200 - 24))
        }
        panel.setFrameAutosaveName("KeepUpWidget")
        self.panel = panel

        // Grow/shrink with the list, keeping the top edge where it is.
        // The minute timer catches day rollovers that regroup the rows.
        cancellable = Store.shared.$items.map { _ in () }
            .merge(with: Timer.publish(every: 60, on: .main, in: .common).autoconnect().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resize() }
            }
    }

    private func resize() {
        guard let panel, let host = panel.contentView else { return }
        let height = max(80, host.fittingSize.height)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: Self.width, height: height)
        panel.setFrame(frame, display: true)
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the very first click on the widget hit a button (mark done)
/// instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct WidgetView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.colorScheme) private var scheme
    private let maxRows = 7

    var body: some View {
        let p = Palette(isDark: scheme == .dark)
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let open = store.openItems
            let shown = Array(open.prefix(maxRows))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("KeepUp")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(p.text)
                    Spacer()
                    Text(open.isEmpty ? "" : "\(open.count) open")
                        .font(.system(size: 11))
                        .foregroundColor(p.faint)
                }
                .contentShape(Rectangle())
                .onTapGesture { AppDelegate.shared?.showMain() }
                .padding(.bottom, 2)

                if shown.isEmpty {
                    Text("All clear ✓")
                        .font(.system(size: 13))
                        .foregroundColor(p.dim)
                        .padding(.vertical, 6)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    let bucket = Due.bucket(item, now: now)
                    if index == 0 || Due.bucket(shown[index - 1], now: now) != bucket {
                        GroupLabel(text: bucket.rawValue, compact: true)
                    }
                    ItemRow(item: item, now: now, compact: true,
                            onToggle: { store.toggleDone(item) },
                            onOpen: { AppDelegate.shared?.showMain(editing: item) })
                }
                if open.count > shown.count {
                    Text("+ \(open.count - shown.count) more")
                        .font(.system(size: 11))
                        .foregroundColor(p.faint)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(width: DesktopWidget.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .themedPanel(cornerRadius: 22)
        }
    }
}
