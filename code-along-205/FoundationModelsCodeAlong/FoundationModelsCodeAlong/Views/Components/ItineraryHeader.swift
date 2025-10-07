/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A SwiftUI view displaying the itinerary header.
*/

import SwiftUI

struct ItineraryHeader: View {
    let destination: Landmark
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(destination.backgroundImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
            Image("\(destination.backgroundImageName)-thumb")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
                .blur(radius: 16, opaque: true)
                .saturation(1.3)
                .brightness(0.15)
                .mask {
                    Rectangle()
                        .fill(
                            Gradient(stops: [
                                .init(color: .clear, location: 0.5),
                                .init(color: .white, location: 0.6)
                            ])
                            .colorSpace(.perceptual)
                        )
                }
        }
        .frame(height: 420)
        .compositingGroup()
        .mask {
            Rectangle()
                .fill(
                    Gradient(stops: [
                        .init(color: .white, location: 0.3),
                        .init(color: .clear, location: 1.0)
                    ])
                    .colorSpace(.perceptual)
                )
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #endif
    }
}
