//
//  GifImage.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 02.01.2026.
//


import SwiftUI
import AppKit
import ImageIO


// MARK: - GIF Image View
struct GifImage: NSViewRepresentable {
    let fileName: String
    var size: CGSize = CGSize(width: 100, height: 100)
    var onFrameInfo: ((GifFrameInfo) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        
        let imageView = NSImageView()
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.canDrawSubviewsIntoLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Load the GIF from the bundle
        if let url = Bundle.main.url(forResource: fileName, withExtension: "gif") {
            if let image = NSImage(contentsOf: url) {
                imageView.image = image
            }
            
            // Extract frame info
            if let frameInfo = extractGifFrameInfo(from: url) {
                DispatchQueue.main.async {
                    onFrameInfo?(frameInfo)
                }
                context.coordinator.startLoopTimer(for: imageView, fileName: fileName, interval: frameInfo.totalDuration)
            } else {
                // Fallback to 5 second loop
                context.coordinator.startLoopTimer(for: imageView, fileName: fileName, interval: 5.0)
            }
        }
        
        containerView.addSubview(imageView)
        
        // Constrain imageView to fill container
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: size.width),
            imageView.heightAnchor.constraint(equalToConstant: size.height)
        ])
        
        return containerView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.animates = true
        }
    }
    
    private func extractGifFrameInfo(from url: URL) -> GifFrameInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        let frameCount = CGImageSourceGetCount(source)
        var frameDurations: [Double] = []
        
        for i in 0..<frameCount {
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                
                // Try unclamped delay time first, then fall back to delay time
                let delay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                
                frameDurations.append(max(delay, 0.01))  // Minimum 10ms
            } else {
                frameDurations.append(0.1)  // Default 100ms
            }
        }
        
        let totalDuration = frameDurations.reduce(0, +)
        
        print("GIF Info: \(frameCount) frames, total duration: \(totalDuration)s")
        print("Frame durations sample: \(frameDurations.prefix(5))...")
        
        return GifFrameInfo(
            totalFrames: frameCount,
            frameDurations: frameDurations,
            totalDuration: totalDuration
        )
    }
    
    class Coordinator {
        var timer: Timer?
        
        func startLoopTimer(for imageView: NSImageView, fileName: String, interval: Double) {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak imageView] _ in
                guard let imageView = imageView else { return }
                
                if let url = Bundle.main.url(forResource: fileName, withExtension: "gif"),
                   let image = NSImage(contentsOf: url) {
                    imageView.image = nil
                    imageView.image = image
                    imageView.animates = true
                }
            }
        }
        
        deinit {
            timer?.invalidate()
        }
    }
}

// MARK: - GIF Frame Info
struct GifFrameInfo {
    let totalFrames: Int
    let frameDurations: [Double]  // Duration for each frame in seconds
    let totalDuration: Double
    
    func timeForFrame(_ frame: Int) -> Double {
        guard frame > 0 && frame <= totalFrames else { return 0 }
        return frameDurations.prefix(frame).reduce(0, +)
    }
}
