//  PiqueApp.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import SwiftUI

@main
struct PiqueApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 720, height: 420)
        .windowResizability(.contentSize)
    }
}
