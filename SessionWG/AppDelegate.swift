//
//  AppDelegate.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//


import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var windows: WindowManager!
    var session: SessionController!
    var auth: AuthCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = WindowManager(state: state)
        auth = AuthCoordinator(state: state, windows: windows)
        session = SessionController(state: state, auth: auth)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if state.status == .connected {
            let alert = NSAlert()
            alert.messageText = "There is a connection running. Are you sure want to quit?"
            alert.addButton(withTitle: "Quit Now")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertSecondButtonReturn {
                return .terminateCancel
            }

            Task {
                await session.disconnect(reason: "app_quit")
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        return .terminateNow
    }
}
