/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A class used to fetch the weather for a location using MapKit.
*/

import Foundation
import MapKit
import os

@Observable @MainActor
final class LocationLookup {

    func mapItem(atLocation location: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location
        
        let search = MKLocalSearch(request: request)
        do {
            return try await search.start().mapItems.first
        } catch {
            print("Failed to look up location: \(location). Error: \(error)")
        }
        return nil
    }
    
}
