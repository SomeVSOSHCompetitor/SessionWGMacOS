//
//  AuthCoordinator.swift
//  SessionWG
//
//  Created by Ustaz1505 on 1/5/26.
//

import Foundation

@MainActor
final class AuthCoordinator: ObservableObject {
    private let state: AppState
    private let windows: WindowManager

    init(state: AppState, windows: WindowManager) {
        self.state = state
        self.windows = windows
    }

    @MainActor
    func ensureAuthenticated() async -> Bool {
        if API.isAccessTokenValid && API.isProofTokenValid {
            state.appendLog("Auth skipped: valid access+proof")
            return true
        }

        if API.isAccessTokenValid && !API.isProofTokenValid {
            state.appendLog("Proof expired, running step-up MFA")

            do {
                let challenge = try await API.stepUpStart()

                guard let code = await windows.requestMFA() else {
                    state.appendLog("Step-up MFA cancelled")
                    return false
                }

                _ = try await API.stepUpVerify(challengeId: challenge.challengeId, totp: code)

                if API.isAccessTokenValid && API.isProofTokenValid {
                    state.appendLog("Step-up ok")
                    return true
                } else {
                    state.appendLog("Step-up finished but tokens not valid (unexpected)")
                    return false
                }
            } catch {
                state.appendLog("Step-up error: \(error.localizedDescription)")
                return false
            }
        }

        state.appendLog("Access expired, running full login")

        guard let creds = await windows.requestLogin() else {
            state.appendLog("Login cancelled")
            return false
        }

        state.appendLog("Got credentials")

        do {
            let challenge = try await API.login(username: creds.username, password: creds.password)

            guard let code = await windows.requestMFA() else {
                state.appendLog("MFA cancelled")
                return false
            }

            _ = try await API.verifyMFA(challengeId: challenge.challengeId, totp: code)

            if API.isAccessTokenValid && API.isProofTokenValid {
                state.appendLog("Full auth ok")
                return true
            } else {
                state.appendLog("Login finished but tokens not valid (unexpected)")
                return false
            }
        } catch {
            state.appendLog("Auth error: \(error.localizedDescription)")
            return false
        }
    }

}
