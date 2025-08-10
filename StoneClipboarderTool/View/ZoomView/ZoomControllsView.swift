//
//  ZoomControllsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 09.08.2025.
//

import SwiftUI

struct ZoomControllsView: View {
    @Binding var zoomScale: CGFloat
    var onFitToWindow: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    zoomScale = max(0.25, zoomScale - 0.25)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomScale <= 0.25)
            .help("Zoom out")
            
            Text("\(Int(zoomScale * 100))%")
                .font(.caption)
                .frame(width: 50)
                .foregroundStyle(.secondary)
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    zoomScale = min(3.0, zoomScale + 0.25)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomScale >= 3.0)
            .help("Zoom in")
            
            Divider()
                .frame(height: 20)
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    zoomScale = 1.0
                }
            } label: {
                Image(systemName: "1.magnifyingglass")
            }
            .help("Reset zoom to 100%")
            
            if let onFitToWindow = onFitToWindow {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        onFitToWindow()
                    }
                } label: {
                    Image(systemName: "rectangle.arrowtriangle.2.inward")
                }
                .help("Fit to window")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
