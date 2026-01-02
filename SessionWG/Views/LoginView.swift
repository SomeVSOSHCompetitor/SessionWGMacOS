//
//  LoginSheet.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/3/26.
//


import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss

    enum Result {
        case cancelled
        case credentials(username: String, password: String)
    }

    let onResult: (Result) -> Void

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Username")
                    TextField("", text: $username).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Password")
                    SecureField("", text: $password).textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onResult(.cancelled)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    onResult(.credentials(username: username, password: password))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.isEmpty || password.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
