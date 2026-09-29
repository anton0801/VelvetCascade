//
//  VelvetCascadeApp.swift
//  VelvetCascade
//
//  Точка входа: создаёт AppEnvironment (или DEBUG fixture из launch arguments) и корневой экран.
//

import SwiftUI

@main
struct VelvetCascadeApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        #if DEBUG
        let fixture = DebugFixture.fromLaunchArguments()
        PerfMonitor.startIfRequested()
        #else
        let fixture: DebugFixture? = nil
        #endif
        _env = StateObject(wrappedValue: AppEnvironment(fixture: fixture))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.router)
                .environmentObject(env.store)
        }
    }
}
