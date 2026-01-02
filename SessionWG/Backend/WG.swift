//
//  WG.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//


import Foundation

enum WG {
    static func up(_ configPath: String) throws {
        try runSudo(["wg-quick", "up", configPath])
    }

    static func down(_ configPath: String) throws {
        try runSudo(["wg-quick", "down", configPath])
    }

    private static func runSudo(_ args: [String]) throws {
        let wgWrapper = "/usr/local/sbin/wg-quick-brewbash"

        guard FileManager.default.fileExists(atPath: wgWrapper) else {
            throw NSError(domain: "WG", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "wg-quick wrapper not found at \(wgWrapper)"])
        }

        let sudoPath = "/usr/bin/sudo"
        let sudoArgs = ["-n", wgWrapper] + Array(args.dropFirst())

        // DEBUG
        print("=== WG DEBUG ===")
        print("Executable:", sudoPath)
        print("Arguments :", sudoArgs.joined(separator: " "))
        print("===============")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: sudoPath)
        p.arguments = sudoArgs

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        try p.run()
        p.waitUntilExit()

        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        print("=== WG RESULT ===")
        print("Exit code:", p.terminationStatus)
        if !outStr.isEmpty { print("STDOUT:\n\(outStr)") }
        if !errStr.isEmpty { print("STDERR:\n\(errStr)") }
        print("=================")

        if p.terminationStatus != 0 {
            let msg = (errStr.isEmpty ? outStr : errStr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "WG", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "wg-quick failed" : msg])
        }
    }
}
