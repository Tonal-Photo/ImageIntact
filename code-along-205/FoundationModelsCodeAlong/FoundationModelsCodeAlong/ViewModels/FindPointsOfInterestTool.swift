/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A tool to use alongside the models to find points of interest for a landmark.
*/

import FoundationModels
import SwiftUI

@Observable
final class FindPointsOfInterestTool: Tool {
    
    // MARK: - [CODE-ALONG] Chapter 5.1.1: Give the tool a name and description
    let name = ""
    let description = ""
    
    let landmark: Landmark
    init(landmark: Landmark) {
        self.landmark = landmark
    }

    @Generable
    struct Arguments {
        // MARK: - [CODE-ALONG] Chapter 5.1.3: Define tool arguments

    }
    
    func call(arguments: Arguments) async throws -> String {
        // MARK: - [CODE-ALONG] Chapter 5.1.4: Implement the tool's call logic
        return ""
    }
    
}

// MARK: - [CODE-ALONG] Chapter 5.1.2: Define searchable categories

func getSuggestions(category: Category, landmark: String) -> [String] {
    // MARK: - [CODE-ALONG] Chapter 5.1.5: Provide mock data for suggestions
    return []
}
