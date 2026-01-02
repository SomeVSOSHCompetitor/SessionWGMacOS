//
//  MenuBarLabel.swift
//  SessionWG
//
//  Created by SomeVSOSHCompetitor on 1/4/26.
//


import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    private var symbolName: String {
        switch state.status {
        case .connecting: return "shield"
        case .connected:  return "lock.shield"
        default:          return "shield.slash"
        }
    }

    var body: some View {
        Image(systemName: symbolName)
    }
}
