//
//  SilhouetteCutout.swift
//  golf-sync-swing
//
//  Dim scrim with a golfer silhouette punched out so the live camera shows
//  through the shape. Used both as a posture preview before recording and
//  inside the countdown overlay.
//

import SwiftUI

struct SilhouetteCutout: View {
    let stance: GolferStance
    var scrimOpacity: Double = 0.55
    var heightFraction: CGFloat = 0.78
    var silhouetteNamespace: Namespace.ID? = nil
    var silhouetteID: AnyHashable = "silhouette"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(scrimOpacity)
                if let assetName = stance.assetName {
                    silhouette(assetName: assetName, in: geo)
                }
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func silhouette(assetName: String, in geo: GeometryProxy) -> some View {
        let image = Image(assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: geo.size.height * heightFraction)
            .blendMode(.destinationOut)

        if let namespace = silhouetteNamespace {
            image.matchedGeometryEffect(id: silhouetteID, in: namespace)
        } else {
            image
        }
    }
}

#Preview("Down the Line") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        SilhouetteCutout(stance: .downTheLine)
    }
}

#Preview("Face-On") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        SilhouetteCutout(stance: .faceOn)
    }
}
