//
//  SessionWGApp.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/2/26.
//

import SwiftUI

@main
struct SessionWGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(appDelegate: appDelegate)
                .environmentObject(appDelegate.state)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}
