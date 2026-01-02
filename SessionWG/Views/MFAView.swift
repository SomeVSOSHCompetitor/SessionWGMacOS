//
//  LoginSheet.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/3/26.
//


import SwiftUI

struct MFAView: View {
    @Environment(\.dismiss) private var dismiss

    enum Result {
        case cancelled
        case code(String)
    }

    let onResult: (Result) -> Void
    @State private var mfa = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter MFA").font(.headline)

            TextField("", text: $mfa)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    onResult(.cancelled)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    onResult(.code(mfa))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mfa.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
