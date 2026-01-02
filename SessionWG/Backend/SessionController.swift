//
//  SessionController.swift
//  SessionWG
//
//  Created by Ustaz1505 on 1/5/26.
//


import Foundation
import Combine


func writeTempConfig(_ content: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("sesswg0.conf")

    try content.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

    return url.path
}

@MainActor
final class SessionController {
    private let state: AppState
    private let authCoordinator: AuthCoordinator
    private var timer: AnyCancellable?
    private var configPath: String?

    init(state: AppState, auth: AuthCoordinator) {
        self.state = state
        self.authCoordinator = auth
    }

    func connect() async {
        guard !state.isBusy else { return }
        state.isBusy = true
        defer { state.isBusy = false }

        state.status = .connecting
        state.appendLog("Starting session")
        
        
        let authenticated = await authCoordinator.ensureAuthenticated()
        if !authenticated {
            state.status = .disconnected
            return
        }

        do {
            let session = try await API.startSession()

            let path = try writeTempConfig(session.wgConfig)
            configPath = path

            try WG.up(path)

            startTTL(seconds: session.ttl)

            state.status = .connected
            state.appendLog("Connected")
        } catch {
            state.status = .error(error.localizedDescription)
            state.appendLog("Error: \(error.localizedDescription)")
        }
    }
    
    func extend() async {
        guard !state.isBusy else { return }
        state.isBusy = true
        defer { state.isBusy = false }

        if state.status != .connected { return }
        
        let authenticated = await authCoordinator.ensureAuthenticated();
        
        if !authenticated { return }
        
        do {
            let updatedTTL = try await API.extendSession()
            if updatedTTL != nil {
                startTTL(seconds: updatedTTL!)
                state.appendLog("Successfully extended session TTL")
            }
        } catch {
            state.appendLog("Error: \(error.localizedDescription)")
        }
    }

    func disconnect(reason: String = "manual") async {
        guard !state.isBusy else { return }
        state.isBusy = true
        defer { state.isBusy = false }

        state.appendLog("Disconnecting (\(reason))")
        timer?.cancel()

        if let path = configPath {
            do { try WG.down(path) }
            catch { state.appendLog("WG down error: \(error.localizedDescription)") }

            try? FileManager.default.removeItem(atPath: path)
            configPath = nil
        }

        do { try await API.stopSession(reason: reason) }
        catch { state.appendLog("API stop error: \(error.localizedDescription)") }

        state.status = .disconnected
        state.ttl = 0
        state.appendLog("Disconnected")
    }

    private func startTTL(seconds: Int) {
        state.ttl = seconds
        timer?.cancel()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.state.ttl > 0 { self.state.ttl -= 1 }
                if self.state.ttl == 0 {
                    Task { await self.disconnect(reason: "ttl_expired") }
                }
            }
    }
}

