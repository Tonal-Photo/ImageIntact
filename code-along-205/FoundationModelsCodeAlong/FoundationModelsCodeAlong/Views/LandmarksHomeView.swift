/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main UI that presents the landmarks.
*/

import SwiftUI

struct LandmarksHomeView: View {

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Where would you like to go today!")
                    .font(.title)
                    .fontWeight(.bold)
                LazyVStack(alignment: .center, spacing: 20) {
                    ForEach(ModelData.landmarks) { landmark in
                        NavigationLink(destination: LandmarkDetailView(landmark: landmark)) {
                            LandmarkListItemView(landmark: landmark)
                                .frame(height: 200)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("")
            .padding(.top, 20)
        }
    }
}

struct LandmarkListItemView: View {
    let landmark: Landmark

    var body: some View {
       
        Image(landmark.thumbnailImageName)
            .resizable()
            .overlay {
                ReadabilityRoundedRectangle()
            }
            .overlay(alignment: .bottomLeading) {
                Text(landmark.name)
                    .font(.title2)
                    .foregroundColor(.white)
                    .bold()
                    .padding()
            }
            .cornerRadius(15.0)
            .clipped()
    }
}
