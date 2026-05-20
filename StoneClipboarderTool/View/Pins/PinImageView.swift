//
//  PinImageView.swift
//  StoneClipboarderTool
//
//  Zoomable / scrollable image renderer used inside a pinned window. Pinch
//  on the trackpad scales the image (MagnificationGesture). Double-click
//  resets zoom to 1.0.
//

import AppKit
import SwiftUI

struct PinImageView: View {
    let imageData: Data?
    @Binding var zoom: Double

    @State private var liveZoom: CGFloat = 1.0

    var body: some View {
        if let data = imageData, let image = NSImage(data: data) {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: max(40, geo.size.width * CGFloat(zoom) * liveZoom),
                            height: max(40, geo.size.height * CGFloat(zoom) * liveZoom)
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    liveZoom = value
                                }
                                .onEnded { value in
                                    let next = max(0.25, min(8.0, zoom * Double(value)))
                                    zoom = next
                                    liveZoom = 1.0
                                }
                        )
                        .onTapGesture(count: 2) {
                            zoom = 1.0
                            liveZoom = 1.0
                        }
                }
                .background(Color.black.opacity(0.04))
            }
        } else {
            ZStack {
                Color.black.opacity(0.04)
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
