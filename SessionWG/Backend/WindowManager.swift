import Cocoa
import SwiftUI

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let state: AppState
    private var settingsWindow: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    // MARK: - Public async API

    @MainActor
    func requestLogin() async -> (username: String, password: String)? {
        await withCheckedContinuation { cont in
            var window: NSWindow!

            let view = LoginView { result in
                switch result {
                case .cancelled:
                    cont.resume(returning: nil)
                case .credentials(let u, let p):
                    cont.resume(returning: (u, p))
                }
                window.orderOut(nil)
            }
            .environmentObject(self.state)

            window = makeWindow(
                title: "Login",
                size: NSSize(width: 460, height: 260),
                rootView: view
            )

            show(window: window)
        }
    }

    func requestMFA() async -> String? {
        await withCheckedContinuation { cont in
            var window: NSWindow!

            let view = MFAView { result in
                switch result {
                case .cancelled:
                    cont.resume(returning: nil)
                case .code(let code):
                    cont.resume(returning: code)
                }
                window.orderOut(nil)
            }
            .environmentObject(self.state)

            window = makeWindow(
                title: "MFA",
                size: NSSize(width: 460, height: 260),
                rootView: view
            )

            show(window: window)
        }
    }
    
    func showSettingsWindow() {
            if settingsWindow == nil {
                settingsWindow = makeWindow(
                    title: "Settings",
                    size: NSSize(width: 460, height: 220),
                    rootView: SettingsView().environmentObject(state)
                )
            }
            show(window: settingsWindow!)
        }
    
    // MARK: - helpers (твои же)

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }

    private func show(window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Если юзер жмёт красный крестик — трактуем как cancel.
    // Но для этого нужно знать, какая continuation висит.
    // Если не хочешь усложнять — можно НЕ перехватывать крестик и просто закрывать.
    // Либо сделать "DialogWindowController" (ниже дам вариант попроще).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
