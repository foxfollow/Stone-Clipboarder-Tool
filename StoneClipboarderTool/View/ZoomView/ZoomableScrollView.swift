//
//  ZoomableScrollView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 09.08.2025.
//

import SwiftUI

struct ZoomableScrollView<Content: View>: View {
    @Binding var zoomLevel: CGFloat
    @Binding var shouldFitToWindow: Bool
    let content: Content
    
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var gestureZoom: CGFloat = 1.0
    @State private var lastGestureZoom: CGFloat = 1.0
    @State private var contentSize: CGSize = .zero
    
    init(
        zoomLevel: Binding<CGFloat>,
        shouldFitToWindow: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self._zoomLevel = zoomLevel
        self._shouldFitToWindow = shouldFitToWindow
        self.content = content()
    }
    
    private var totalZoom: CGFloat {
        zoomLevel * gestureZoom
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                content
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .onAppear {
                                    contentSize = contentGeometry.size
                                }
                                .onChange(of: contentGeometry.size) { _, newSize in
                                    contentSize = newSize
                                }
                        }
                    )
                    .scaleEffect(totalZoom, anchor: .topLeading)
                    .offset(offset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: offset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: zoomLevel)
            }
            .scrollDisabled(totalZoom <= 1.0)
            .clipped()
            .onAppear {
                resetZoomAndOffset(geometry: geometry)
            }
            .onChange(of: zoomLevel) { _, _ in
                gestureZoom = 1.0
                lastGestureZoom = 1.0
                limitOffset(geometry: geometry)
            }
            .onChange(of: contentSize) { _, _ in
                resetZoomAndOffset(geometry: geometry)
            }
            .onChange(of: shouldFitToWindow) { _, shouldFit in
                if shouldFit {
                    fitToWindow(geometry: geometry)
                    shouldFitToWindow = false
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        gestureZoom = max(0.25 / zoomLevel, min(3.0 / zoomLevel, lastGestureZoom * value))
                    }
                    .onEnded { _ in
                        let newZoom = totalZoom
                        zoomLevel = max(0.25, min(3.0, newZoom))
                        gestureZoom = 1.0
                        lastGestureZoom = 1.0
                        limitOffset(geometry: geometry)
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if totalZoom > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                        limitOffset(geometry: geometry)
                    }
            )
        }
    }
    
    private func resetZoomAndOffset(geometry: GeometryProxy) {
        guard contentSize.width > 0 && contentSize.height > 0 else { return }
        
        // Calculate zoom to fit
        let scaleX = geometry.size.width / contentSize.width
        let scaleY = geometry.size.height / contentSize.height
        let fitZoom = min(scaleX, scaleY, 1.0)
        
        // Set zoom to fit or 1.0, whichever is smaller
        zoomLevel = fitZoom
        gestureZoom = 1.0
        lastGestureZoom = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    private func fitToWindow(geometry: GeometryProxy) {
        guard contentSize.width > 0 && contentSize.height > 0 else { return }
        
        let scaleX = geometry.size.width / contentSize.width
        let scaleY = geometry.size.height / contentSize.height
        let fitZoom = min(scaleX, scaleY)
        
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8)) {
            zoomLevel = max(0.25, min(3.0, fitZoom))
            offset = .zero
        }
        
        gestureZoom = 1.0
        lastGestureZoom = 1.0
        lastOffset = .zero
    }
    
    private func limitOffset(geometry: GeometryProxy) {
        let scaledContentWidth = contentSize.width * totalZoom
        let scaledContentHeight = contentSize.height * totalZoom
        
        let maxOffsetX = max(0, (scaledContentWidth - geometry.size.width) / 2)
        let maxOffsetY = max(0, (scaledContentHeight - geometry.size.height) / 2)
        
        let limitedX = max(-maxOffsetX, min(maxOffsetX, offset.width))
        let limitedY = max(-maxOffsetY, min(maxOffsetY, offset.height))
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            offset = CGSize(width: limitedX, height: limitedY)
        }
        lastOffset = offset
    }
}

