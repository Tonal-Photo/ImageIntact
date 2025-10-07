/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The main function for the FoundationModelsCodeAlong app.
*/

import SwiftUI

@main
struct FoundationModelsCodeAlongApp: App {
    private var modelData = ModelData.shared
    
    var body: some Scene {
        WindowGroup {
            LandmarksHomeView()
                .environment(modelData)
                #if os(macOS)
                .frame(width: 500, height: 800)
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
