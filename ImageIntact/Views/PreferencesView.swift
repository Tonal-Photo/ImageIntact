//
//  PreferencesView.swift
//  ImageIntact
//
//  Application preferences window — tab container. Individual tabs live in their own files:
//  GeneralPreferencesView, PerformancePreferencesView, LoggingPreferencesView, AdvancedPreferencesView.
//

import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab = "general"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralPreferencesView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag("general")

                PerformancePreferencesView()
                    .tabItem {
                        Label("Performance", systemImage: "cpu")
                    }
                    .tag("performance")

                LoggingPreferencesView()
                    .tabItem {
                        Label("Logging & Privacy", systemImage: "lock.shield")
                    }
                    .tag("logging")

                AdvancedPreferencesView()
                    .tabItem {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
                    .tag("advanced")
            }
            .padding(.top, 10)

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .padding(.trailing, 20)
                .padding(.vertical, 12)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 650, height: 560)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
