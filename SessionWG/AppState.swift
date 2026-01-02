//
//  AppState.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//


import Foundation
import Combine


struct LogLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
}


@MainActor
final class AppState: ObservableObject {
    // UI state
    @Published var status: Status = .disconnected
    @Published var ttl: Int = 0
    @Published var log: [LogLine] = []
    @Published var isBusy: Bool = false
    @Published var serverURLString: String = ""

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    func appendLog(_ text: String) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        log.insert(LogLine(text: "[\(timestamp)] \(text)"), at: 0)
    }

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()
}
