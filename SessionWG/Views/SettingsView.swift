//
//  SettingsView.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//


import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState

    @State private var urlText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Server URL")
                    TextField("https://example.com", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    state.serverURLString = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            urlText = state.serverURLString
        }
    }
}
