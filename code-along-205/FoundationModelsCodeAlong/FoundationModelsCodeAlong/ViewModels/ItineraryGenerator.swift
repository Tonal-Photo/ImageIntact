/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A class that generates an itinerary.
*/

import FoundationModels
import Observation

@Observable
@MainActor
final class ItineraryGenerator {
    
    var error: Error?
    let landmark: Landmark
    
    // MARK: - [CODE-ALONG] Chapter 1.5.1: Add a session property
    
    // MARK: - [CODE-ALONG] Chapter 2.3.1: Update to Generable
    // MARK: - [CODE-ALONG] Chapter 4.1.1: Change the property to hold a partially generated Itinerary
    private(set) var itineraryContent: String?

    init(landmark: Landmark) {
        self.landmark = landmark
        // MARK: - [CODE-ALONG] Chapter 1.5.2: Initialize LanguageModelSession
        // MARK: - [CODE-ALONG] Chapter 2.3.3: Update instructions to remove structural guidance
        // MARK: - [CODE-ALONG] Chapter 5.3.1: Update the instructions to use the Tool
        // MARK: - [CODE-ALONG] Chapter 5.3.2: Update the LanguageModelSession with the tool
               
    }

    func generateItinerary(dayCount: Int = 3) async {
        // MARK: - [CODE-ALONG] Chapter 1.5.3: Add itinerary generator using Foundation Models
        // MARK: - [CODE-ALONG] Chapter 2.3.2: Update to use Generables
        // MARK: - [CODE-ALONG] Chapter 3.3: Update to use one-shot prompting
        // MARK: - [CODE-ALONG] Chapter 4.1.2: Update to use streaming API
        // MARK: - [CODE-ALONG] Chapter 5.3.3: Update `session.streamResponse` to include greedy sampling
        // MARK: - [CODE-ALONG] Chapter 6.2.1: Update to exclude schema from prompt
         
    }

    func prewarmModel() {
        // MARK: - [CODE-ALONG] Chapter 6.1.1: Add a function to pre-warm the model
    }
}
