/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A SwiftUI view for rendering each day's suggested events.
*/

import FoundationModels
import SwiftUI
import MapKit

struct ItineraryView: View {
    let landmark: Landmark
    // MARK: - [CODE-ALONG] Chapter 4.2.1: Update to accept PartiallyGenerated type
    let itinerary: Itinerary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                // MARK: - [CODE-ALONG] Chapter 4.2.2: Update to unwrap all PartiallyGenerated types
                Text(itinerary.title)
                    .contentTransition(.opacity)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // MARK: - [CODE-ALONG] Chapter 4.2.2: Update to unwrap all PartiallyGenerated types
                Text(itinerary.description)
                    .contentTransition(.opacity)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                // MARK: - [CODE-ALONG] Chapter 4.2.2: Update to unwrap all PartiallyGenerated types
                Text(itinerary.rationale)
                    .contentTransition(.opacity)
                .rationaleStyle()
            }
            
            // MARK: - [CODE-ALONG] Chapter 4.2.2: Update to unwrap all PartiallyGenerated types
            ForEach(itinerary.days, id: \.title) { plan in
                DayView(
                    landmark: landmark,
                    plan: plan
                )
            }

        }
        .animation(.easeOut, value: itinerary)
        .itineraryStyle()
    }
}

// MARK: - [CODE-ALONG] Chapter 4.2.3: Update to unwrap all PartiallyGenerated types
private struct DayView: View {
    let landmark: Landmark
    // MARK: - [CODE-ALONG] Chapter 4.2.1: Update to accept PartiallyGenerated type
    let plan: DayPlan

    @State private var mapItem: MKMapItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottom) {
                LandmarkDetailMapView(
                    landmark: landmark,
                    landmarkMapItem: mapItem
                )
                
                .task(id: plan.destination) {
                    guard !plan.destination.isEmpty else { return }
                    
                    if let fetchedItem = await LocationLookup().mapItem(atLocation: plan.destination) {
                        self.mapItem = fetchedItem
                    }
                }
                
                VStack(alignment: .leading) {
                    
                    Text(plan.title)
                            .contentTransition(.opacity)
                            .font(.headline)

                        Text(plan.subtitle)
                            .contentTransition(.opacity)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blurredBackground()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .padding([.horizontal, .top], 4)
            
            ActivityList(activities: plan.activities)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        .padding(.bottom)
        .geometryGroup()
        .card()
        .animation(.easeInOut, value: plan)
    }
      
}

private struct ActivityList: View {
    // MARK: - [CODE-ALONG] Chapter 4.2.1: Update to accept PartiallyGenerated type
    let activities: [Activity]
    
    var body: some View {
        ForEach(activities, id: \.title) { activity in
            HStack(alignment: .top, spacing: 12) {
                    ActivityIcon(symbolName: activity.type.symbolName)
                VStack(alignment: .leading) {
                    Text(activity.title)
                        .contentTransition(.opacity)
                        .font(.headline)
                    Text(activity.description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
