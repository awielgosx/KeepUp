import AppKit
import SwiftUI

@main
struct KeepUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The main window and desktop widget are AppKit windows owned by
        // AppDelegate (so the widget can open the main window directly);
        // SwiftUI only provides the Settings window and menu commands.
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Item") { AppDelegate.shared?.showMain(editing: Item()) }
                    .keyboardShortcut("n")
                Button("Show KeepUp") { AppDelegate.shared?.showMain() }
                    .keyboardShortcut("0")
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Desktop Widget") {
                    let on = !UserDefaults.standard.bool(forKey: Pref.widgetOn)
                    UserDefaults.standard.set(on, forKey: Pref.widgetOn)
                    DesktopWidget.shared.refreshVisibility()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        UserDefaults.standard.register(defaults: [Pref.widgetOn: true, Pref.theme: ThemePref.auto.rawValue])
        ThemePref.apply()
        DesktopWidget.shared.refreshVisibility()
        // Started at login → just the widget; started by hand → the window too.
        if !launchedAsLoginItem() { showMain() }
        Store.shared.sync()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep the desktop widget alive
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Store.shared.sync()
    }

    func showMain(editing item: Item? = nil) {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "KeepUp"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView())
            window.setContentSize(NSSize(width: 440, height: 640))
            window.center()
            window.setFrameAutosaveName("KeepUpMain")
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let item {
            UIState.shared.editing = item
        }
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
