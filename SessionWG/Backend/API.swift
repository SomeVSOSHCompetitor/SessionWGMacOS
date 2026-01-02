//
//  API.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//

import Foundation
import CryptoKit

enum API {

    // MARK: - Public types

    struct Session {
        let wgConfig: String
        let ttl: Int
    }
    
    struct MFAChallenge {
        let challengeId: String
        let challengeExpiresAt: Date
    }

    struct SuccessStepUp {
        let proofToken: String
        let proofTokenExpiresAt: Date
    }
    
    struct SuccessLogin {
        let accessToken: String
        let accessTokenExpiresAt: Date
        let proofToken: String
        let proofTokenExpiresAt: Date
    }

    // MARK: - Config

    /// Пример: URL(string: "https://vpn.example.com")!
    static var baseURL: URL = URL(string: "http://test-vpn-gw.spoverlay.ru:8000")!

    /// Если бэк использует self-signed/внутренний CA — НЕ отключай валидацию TLS.
    /// Лучше завези нормальный сертификат или пиннинг публичного ключа (URLSessionDelegate).
    static var defaultTimeout: TimeInterval = 10

    // MARK: - In-memory state (лучше: Keychain + Secure Enclave где возможно)

    private static var accessToken: String?
    private static var accessExpiresAt: Date?
    private static var currentSessionId: String?
    private static var currentClientPrivateKeyBase64: String? // нужен чтобы собрать wgConfig
    private static var currentExpiresAt: Date?

    private static var proofToken: String?
    private static var proofExpiresAt: Date?


    // MARK: - Errors

    enum APIError: Error, LocalizedError {
        case missingAccessToken
        case missingProofToken
        case missingSessionId
        case invalidURL
        case http(status: Int, body: String)
        case decodeFailed
        case credentialsRequired
        case invalidTOTP
        case missingClientPrivateKey

        var errorDescription: String? {
            switch self {
            case .missingAccessToken: return "No access token (need auth + MFA)."
            case .missingProofToken: return "No proof token (need to create session or refresh it first)."
            case .missingSessionId: return "No current session id."
            case .invalidURL: return "Invalid URL."
            case .http(let status, let body): return "HTTP \(status): \(body)"
            case .decodeFailed: return "Failed to decode response."
            case .credentialsRequired: return "Credentials required."
            case .invalidTOTP: return "Invalid TOTP format (must be 6 digits)."
            case .missingClientPrivateKey: return "Client private key missing."
            }
        }
    }

    // MARK: - OpenAPI models (user endpoints only)

    // /v1/auth/start
    private struct AuthStartRequest: Codable {
        let username: String
        let password: String
    }
    private struct AuthStartResponse: Codable {
        let challenge_id: String
        let mfa_required: Bool?
        let challenge_expires_in: Int
    }

    // /v1/auth/verify-mfa
    private struct VerifyMfaRequest: Codable {
        let challenge_id: String
        let totp_code: String
    }
    private struct VerifyMfaResponse: Codable {
        let access_token: String
        let access_expires_in: Int
        let proof_token: String
        let proof_expires_in: Int
    }
    
    // /v1/auth/step-up/start
    private struct StepUpStartResponse: Codable {
        let challenge_id: String
        let challenge_expires_in: Int
    }
    
    // /v1/auth/step-up/verify
    private struct StepUpVerifyResponse: Codable {
        let proof_token: String
        let proof_expires_in: Int
    }

    // /v1/sessions
    private struct SessionCreateRequest: Codable {
        let client_pubkey: String
        let ttl_step_seconds: Int?
    }
    private struct SessionCreateResponse: Codable {
        let session_id: String
        let started_at: String
        let expires_at: String
        let max_expires_at: String
        let status: String
    }

    // /v1/sessions/{session_id}
    private struct SessionStatusResponse: Codable {
        let session_id: String
        let status: String
        let started_at: String
        let expires_at: String
        let max_expires_at: String
        let remaining_seconds: Int
    }

    // /v1/sessions/{session_id}/revoke
    private struct SessionRevokeResponse: Codable {
        let status: String
        let revoked_at: String
    }

// /v1/sessions/{session_id}/config
    private struct SessionConfigResponse: Codable {
        let interface: WgInterface
        let peer: WgPeer
    }
    private struct WgInterface: Codable {
        let address: String
        let dns: [String]
    }
    private struct WgPeer: Codable {
        let public_key: String
        let endpoint: String
        let allowed_ips: [String]
        let persistent_keepalive: Int?
    }
    
    private struct RenewVerifyResponse: Codable {
        let status: String
        let expires_at: String
        let max_expires_at: String
    }

    // MARK: - WireGuard keypair generation (new key each session)

    private struct WGKeyPair {
        let privateKeyBase64: String
        let publicKeyBase64: String

        static func generate() -> WGKeyPair {
            // WireGuard uses X25519 (Curve25519) keys, base64-encoded raw 32 bytes.
            let priv = Curve25519.KeyAgreement.PrivateKey()
            let pub = priv.publicKey

            let privRaw = priv.rawRepresentation
            let pubRaw = pub.rawRepresentation

            return WGKeyPair(
                privateKeyBase64: Data(privRaw).base64EncodedString(),
                publicKeyBase64: Data(pubRaw).base64EncodedString()
            )
        }
    }

    // MARK: - Public high-level flow
    
    /// Полный пользовательский флоу по спеке:
    /// 1) генерим НОВЫЙ WG keypair на клиенте
    /// 2) /v1/sessions (Authorization: Bearer ...)
    /// 3) /v1/sessions/{id}/config (Authorization: Bearer ...)
    /// 4) собираем wg-quick конфиг и возвращаем ttl=remaining_seconds
    static func startSession(
        ttlStepSeconds: Int? = nil
    ) async throws -> Session {
        // 1) new WG keys for THIS session
        let keys = WGKeyPair.generate()
        currentClientPrivateKeyBase64 = keys.privateKeyBase64

        // 2) create session with client_pubkey
        let created = try await createSessionRequest(clientPubkey: keys.publicKeyBase64, ttlStepSeconds: ttlStepSeconds)
        currentSessionId = created.session_id
        currentExpiresAt = iso8601Date(created.expires_at)

        
        // 3) get config
        let cfg = try await sessionConfigRequest(sessionId: created.session_id)

        // 4) build wg-quick config
        let wgText = try buildWgQuickConfig(
            clientPrivateKeyBase64: keys.privateKeyBase64,
            interface: cfg.interface,
            peer: cfg.peer
        )

        // TTL for UI: лучше брать у /status, но у нас уже есть remainingSeconds при желании
        // Здесь возьмем status, чтобы получить remaining_seconds точнее.
        let st = try await sessionStatusRequest(sessionId: created.session_id)

        return Session(wgConfig: wgText, ttl: st.remaining_seconds)
    }
    
    static func extendSession() async throws -> Int? {
        if currentSessionId == nil { return nil }
        let updatedSession = try await renewVerifyRequest(sessionId: currentSessionId!)
        let st = try await sessionStatusRequest(sessionId: currentSessionId!)
        return st.remaining_seconds
    }

/// Остановка: revoke текущей сессии (user endpoint).
    static func stopSession(reason: String) async throws {
        _ = reason // в спеке reason нет; если нужно — добавь на бэке.
        guard let sid = currentSessionId else { throw APIError.missingSessionId }
        _ = try await revokeSessionRequest(sessionId: sid)

        // чистим локальный state
        currentSessionId = nil
        currentExpiresAt = nil
        currentClientPrivateKeyBase64 = nil
//        // accessToken можно оставить для новой сессии или стереть — твой выбор.
//        // Для безопасности лучше стереть при disconnect:
//        accessToken = nil
//        
//        // Стираем временный proofToken
//        proofToken = nil
//        proofExpiresAt = nil
    }
    // MARK: - Public token validity properties
    static var isAccessTokenValid: Bool {
        guard
            let token = accessToken,
            !token.isEmpty,
            let expiresAt = accessExpiresAt
        else {
            return false
        }

        return Date() < expiresAt
    }

    static var isProofTokenValid: Bool {
        guard
            let token = proofToken,
            !token.isEmpty,
            let expiresAt = proofExpiresAt
        else {
            return false
        }

        return Date() < expiresAt
    }
    
    
    // MARK: - Main flow
    
    static func login(username: String, password: String) async throws -> MFAChallenge {
        let r: AuthStartResponse = try await authStartRequest(username: username, password: password);
        return MFAChallenge(
            challengeId: r.challenge_id,
            challengeExpiresAt: Date(timeInterval: TimeInterval(r.challenge_expires_in), since: Date())
        )
    }
    
    static func verifyMFA(challengeId: String, totp: String) async throws -> SuccessLogin {
        guard totp.count == 6, totp.allSatisfy({ $0.isNumber }) else {
            throw APIError.invalidTOTP
        }
        
        let r: VerifyMfaResponse = try await verifyMfaRequest(challengeId: challengeId, totp: totp);
        
        accessToken = r.access_token
        accessExpiresAt = Date(timeInterval: TimeInterval(r.access_expires_in), since: Date())
        proofToken = r.proof_token
        proofExpiresAt = Date(timeInterval: TimeInterval(r.proof_expires_in), since: Date())
        
        return SuccessLogin(
            accessToken: r.access_token,
            accessTokenExpiresAt: Date(timeInterval: TimeInterval(r.access_expires_in), since: Date()),
            proofToken: r.proof_token,
            proofTokenExpiresAt: Date(timeInterval: TimeInterval(r.proof_expires_in), since: Date())
        )
    }
    
    // MARK: - Step-up flow
    
    static func stepUpStart() async throws -> MFAChallenge {
        let r: StepUpStartResponse = try await stepUpStartRequest();
        return MFAChallenge(
            challengeId: r.challenge_id,
            challengeExpiresAt: Date(timeInterval: TimeInterval(r.challenge_expires_in), since: Date())
        )
    }
    
    static func stepUpVerify(challengeId: String, totp: String) async throws -> SuccessStepUp {
        let r: StepUpVerifyResponse = try await stepUpVerifyRequest(challengeId: challengeId, totp: totp);
        
        proofToken = r.proof_token
        proofExpiresAt = Date(timeInterval: TimeInterval(r.proof_expires_in), since: Date())
        
        return SuccessStepUp(
            proofToken: r.proof_token,
            proofTokenExpiresAt: Date(timeInterval: TimeInterval(r.proof_expires_in), since: Date())
        )
    }

    // MARK: - Low-level endpoint wrappers

    private static func authStartRequest(username: String, password: String) async throws -> AuthStartResponse {
        try await request(
            path: "/v1/auth/start",
            method: "POST",
            body: AuthStartRequest(username: username, password: password),
            auth: .none,
            headerOverrides: [:]
        )
    }
    
    private static func verifyMfaRequest(challengeId: String, totp: String) async throws -> VerifyMfaResponse {
        try await request(
            path: "/v1/auth/verify-mfa",
            method: "POST",
            body: VerifyMfaRequest(challenge_id: challengeId, totp_code: totp),
            auth: .none,
            headerOverrides: [:]
        )
    }
    
    private static func stepUpStartRequest() async throws -> StepUpStartResponse {
        try await request(
            path: "/v1/auth/step-up/start",
            method: "POST",
            auth: .bearerRequired,
            headerOverrides: [:]
        )
    }
    
    private static func stepUpVerifyRequest(challengeId: String, totp: String) async throws -> StepUpVerifyResponse {
        try await request(
            path: "/v1/auth/step-up/verify",
            method: "POST",
            body: VerifyMfaRequest(challenge_id: challengeId, totp_code: totp),
            auth: .bearerRequired,
            headerOverrides: [:]
        )
    }

    private static func createSessionRequest(clientPubkey: String, ttlStepSeconds: Int?) async throws -> SessionCreateResponse {
        try await request(
            path: "/v1/sessions",
            method: "POST",
            body: SessionCreateRequest(client_pubkey: clientPubkey, ttl_step_seconds: ttlStepSeconds),
            auth: .proofRequired,
            headerOverrides: [:]
        )
    }

    private static func sessionStatusRequest(sessionId: String) async throws -> SessionStatusResponse {
        try await request(
            path: "/v1/sessions/\(sessionId)",
            method: "GET",
            auth: .bearerRequired,
            headerOverrides: [:]
        )
    }

    private static func sessionConfigRequest(sessionId: String) async throws -> SessionConfigResponse {
        try await request(
            path: "/v1/sessions/\(sessionId)/config",
            method: "POST",
            auth: .proofRequired,
            headerOverrides: [:]
        )
    }

    private static func revokeSessionRequest(sessionId: String) async throws -> SessionRevokeResponse {
        try await request(
            path: "/v1/sessions/\(sessionId)/revoke",
            method: "POST",
            auth: .bearerRequired,
            headerOverrides: [:]
        )
    }

    private static func renewVerifyRequest(sessionId: String) async throws -> RenewVerifyResponse {
        try await request(
            path: "/v1/sessions/\(sessionId)/renew",
            method: "POST",
            auth: .proofRequired,
            headerOverrides: [:]
        )
    }

    // MARK: - HTTP core
    // Внутри enum API, но ВНЕ функций:
    private struct EmptyBody: Encodable {
        init() {}
    }

    private enum AuthMode {
        case none
        case bearerRequired       // user access token
        case proofRequired        // mfa proof token
    }

    private static func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        auth: AuthMode,
        headerOverrides: [String: String]
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = defaultTimeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let hasBody = (body != nil) && (method != "GET")
        if hasBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        switch auth {
        case .none:
            break
        case .bearerRequired:
            guard let tok = accessToken else { throw APIError.missingAccessToken }
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        case .proofRequired:
            guard let tok = proofToken else { throw APIError.missingProofToken }
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }

        for (k, v) in headerOverrides {
            req.setValue(v, forHTTPHeaderField: k)
        }

        if hasBody, let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: "No HTTPURLResponse")
        }

        if !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            throw APIError.http(status: http.statusCode, body: text)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodeFailed
        }
    }

    /// Перегрузка для запросов БЕЗ body (GET и POST без JSON)
    private static func request<T: Decodable>(
        path: String,
        method: String,
        auth: AuthMode,
        headerOverrides: [String: String]
    ) async throws -> T {
        if method == "GET" {
            return try await request(path: path, method: method, body: Optional<EmptyBody>.none, auth: auth, headerOverrides: headerOverrides)
        } else {
            // POST без payload — отправим пустой JSON {} (совместимо с FastAPI)
            return try await request(path: path, method: method, body: EmptyBody(), auth: auth, headerOverrides: headerOverrides)
        }
    }
    // MARK: - Config builder

    private static func buildWgQuickConfig(
        clientPrivateKeyBase64: String,
        interface: WgInterface,
        peer: WgPeer
    ) throws -> String {
        // Важно: PrivateKey всегда ТОЛЬКО в RAM. Не логировать. Не писать в файлы без необходимости.
        let dnsLine = interface.dns.joined(separator: ", ")
        let allowed = peer.allowed_ips.joined(separator: ", ")
        let keepalive = peer.persistent_keepalive ?? 25

return """
        [Interface]
        PrivateKey = \(clientPrivateKeyBase64)
        Address = \(interface.address)
        DNS = \(dnsLine)

        [Peer]
        PublicKey = \(peer.public_key)
        Endpoint = \(peer.endpoint)
        AllowedIPs = \(allowed)
        PersistentKeepalive = \(keepalive)
        """
    }

    // MARK: - Date helper

    private static func iso8601Date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        // FastAPI обычно отдаёт ISO8601 с timezone
        return f.date(from: s)
    }
}
