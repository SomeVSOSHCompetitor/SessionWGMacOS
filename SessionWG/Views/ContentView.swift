//
//  ContentView.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/2/26.
//


import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    var appDelegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text(statusText)
                .font(.headline)

            
            if state.status == .connected {
                Text("Expires in \(state.ttl)s")
                    .font(.caption)
            }

            HStack {
                if state.status == .connected {
                    Button("Disconnect") {
                        Task { await appDelegate.session.disconnect(reason: "manual") }
                    }
                    .disabled(state.status != .connected)
                    
                    Button("Extend session") {
                        Task { await appDelegate.session.extend() }
                    }
                    .disabled(state.status != .connected)
                } else {
                    Button("Connect") {
                        Task { await appDelegate.session.connect() }
                    }
                    .disabled(state.status != .disconnected)
                }
            }

            HStack {
                Button("Settings…") { appDelegate.windows.showSettingsWindow() }
            }

            Divider()

            let logHeight: CGFloat = 140

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.log) { item in
                            Text(item.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(item.id)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: logHeight, alignment: .topLeading)
                    .padding(.trailing, 8)
                }
                .frame(height: logHeight)
                .onChange(of: state.log.first?.id) { _, firstId in
                    guard let firstId else { return }
                    proxy.scrollTo(firstId, anchor: .topLeading)
                }
                .onAppear {
                    if let firstId = state.log.first?.id {
                        proxy.scrollTo(firstId, anchor: .topLeading)
                    }
                }
            }
        }
        .padding()
        .frame(width: 320)

    }

    private var statusText: String {
        switch state.status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let e): return "Error: \(e)"
        }
    }
}
