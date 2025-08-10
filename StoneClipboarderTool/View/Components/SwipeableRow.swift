//
//  SwipeableRow.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI
import AppKit

enum SwipeAction {
    case none
    case delete
    case openMain
}

// NSViewRepresentable for two-finger swipe detection that allows normal scrolling
struct TwoFingerSwipeDetector: NSViewRepresentable {
    let onSwipeUpdate: (CGFloat) -> Void
    let onSwipeEnded: (SwipeAction) -> Void
    
    func makeNSView(context: Context) -> TwoFingerSwipeNSView {
        let view = TwoFingerSwipeNSView()
        view.onSwipeUpdate = onSwipeUpdate
        view.onSwipeEnded = onSwipeEnded
        return view
    }
    
    func updateNSView(_ nsView: TwoFingerSwipeNSView, context: Context) {
        nsView.onSwipeUpdate = onSwipeUpdate
        nsView.onSwipeEnded = onSwipeEnded
    }
}

class TwoFingerSwipeNSView: NSView {
    var onSwipeUpdate: ((CGFloat) -> Void)?
    var onSwipeEnded: ((SwipeAction) -> Void)?
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var isTrackingSwipe = false
    private let swipeThreshold: CGFloat = 100
    private let verticalTolerance: CGFloat = 50
    private var eventMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        setupEventMonitoring()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        setupEventMonitoring()
    }
    
    private func setupEventMonitoring() {
        // Monitor scroll wheel events at the application level
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            
            // Check if the event is within our bounds
            if let window = self.window {
                let locationInWindow = event.locationInWindow
                let locationInView = self.convert(locationInWindow, from: nil)
                
                if self.bounds.contains(locationInView) {
                    self.handleScrollWheel(with: event)
                }
            }
            
            return event // Always return the event to allow normal scrolling
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    private func handleScrollWheel(with event: NSEvent) {
        // Only handle precise trackpad gestures
        guard event.hasPreciseScrollingDeltas else {
            return
        }
        
        switch event.phase {
        case .began:
            accumulatedDeltaX = 0
            accumulatedDeltaY = 0
            isTrackingSwipe = true
            
        case .changed:
            if isTrackingSwipe {
                accumulatedDeltaX += event.scrollingDeltaX
                accumulatedDeltaY += abs(event.scrollingDeltaY)
                
                // Only handle horizontal swipes with minimal vertical movement
                if accumulatedDeltaY < verticalTolerance {
                    // Update the visual offset during swipe (allow both directions)
                    let clampedOffset = max(-150, min(150, accumulatedDeltaX * 0.8)) // Add resistance both ways
                    onSwipeUpdate?(clampedOffset)
                }
            }
            
        case .ended:
            if isTrackingSwipe {
                let shouldDelete = accumulatedDeltaX < -swipeThreshold && accumulatedDeltaY < verticalTolerance
                let shouldOpenMain = accumulatedDeltaX > swipeThreshold && accumulatedDeltaY < verticalTolerance
                
                if accumulatedDeltaY < verticalTolerance {
                    // This was a horizontal swipe gesture
                    if shouldDelete {
                        onSwipeEnded?(.delete)  // Delete action (left swipe)
                    } else if shouldOpenMain {
                        onSwipeEnded?(.openMain) // Open main window action (right swipe)
                    } else {
                        onSwipeEnded?(.none) // No action, just reset
                    }
                }
            }
            isTrackingSwipe = false
            
        case .cancelled:
            if isTrackingSwipe && accumulatedDeltaY < verticalTolerance {
                onSwipeEnded?(.none)
            }
            isTrackingSwipe = false
            
        default:
            break
        }
    }
}

// SwiftUI-native deletable row with visual swipe feedback and action buttons
struct SwipeableRow<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    let item: CBItem?
    let onPreview: ((CBItem) -> Void)?
    let onOpenMain: ((CBItem) -> Void)?
    
    @FocusState private var isFocused: Bool
    @State private var swipeOffset: CGFloat = 0
    @State private var isDeleting = false
    @State private var showActionButtons = false
    
    // Computed property to determine if Preview button should be shown
    private var shouldShowPreviewButton: Bool {
        guard let item = item else { return false }
        switch item.itemType {
        case .image:
            return item.image != nil
        case .file:
            return item.isImageFile && item.filePreviewImage != nil
        case .text:
            return false
        }
    }
    
    init(@ViewBuilder content: () -> Content, onDelete: @escaping () -> Void) {
        self.content = content()
        self.onDelete = onDelete
        self.item = nil
        self.onPreview = nil
        self.onOpenMain = nil
    }
    
    init(
        item: CBItem,
        onDelete: @escaping () -> Void,
        onPreview: @escaping (CBItem) -> Void,
        onOpenMain: @escaping (CBItem) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onDelete = onDelete
        self.item = item
        self.onPreview = onPreview
        self.onOpenMain = onOpenMain
    }
    
    var body: some View {
        HStack(spacing: 0) {
            content
                .focusable()
                .focused($isFocused)
                .offset(x: swipeOffset)
                .background(
                    Rectangle()
                        .fill(
                            swipeOffset < -50 ? Color.red.opacity(0.1) : 
                            swipeOffset > 50 ? Color.green.opacity(0.1) : 
                            Color.clear
                        )
                        .animation(.easeOut(duration: 0.1), value: swipeOffset)
                )
                .scaleEffect(isDeleting ? 0.95 : 1.0)
                .opacity(isDeleting ? 0.7 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDeleting)
                .overlay(
                    // Transparent overlay to capture scroll events only
                    TwoFingerSwipeDetector(
                        onSwipeUpdate: { offset in
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                swipeOffset = offset
                                showActionButtons = offset < -60
                            }
                        },
                        onSwipeEnded: { action in
                            switch action {
                            case .delete:
                                performDelete()
                            case .openMain:
                                if let item = item, let onOpenMain = onOpenMain {
                                    resetSwipeState()
                                    onOpenMain(item)
                                } else {
                                    resetSwipeState()
                                }
                            case .none:
                                resetSwipeState()
                            }
                        }
                    )
                    .allowsHitTesting(false)
                )
                .onDeleteCommand {
                    performDelete()
                }
                .onTapGesture {
                    isFocused = true
                }
                .contextMenu {
                    // Preview button in context menu
                    if shouldShowPreviewButton, let item = item, let onPreview = onPreview {
                        Button("Open in Preview") {
                            onPreview(item)
                        }
                    }
                    
                    // Open in Main Window button in context menu
                    if let item = item, let onOpenMain = onOpenMain {
                        Button("Open in Main Window") {
                            onOpenMain(item)
                        }
                    }
                    
                    // Add separator if we have other actions
                    if item != nil && (onPreview != nil || onOpenMain != nil) {
                        Divider()
                    }
                    
                    Button("Delete123", role: .destructive) {
                        performDelete()
                    }
                }
            
            // Action buttons that appear during swipe
            if showActionButtons {
                HStack(spacing: 4) {
                    // Preview button (only for image items)
                    if shouldShowPreviewButton, let item = item, let onPreview = onPreview {
                        Button {
                            resetSwipeState()
                            onPreview(item)
                        } label: {
                            Image(systemName: "eye")
                                .foregroundColor(.white)
                                .frame(width: 45, height: 40)
                                .background(Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Open in Main Window button
                    if let item = item, let onOpenMain = onOpenMain {
                        Button {
                            resetSwipeState()
                            onOpenMain(item)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.white)
                                .frame(width: 45, height: 40)
                                .background(Color.green)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Delete button
                    Button {
                        performDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 45, height: 40)
                            .background(Color.red)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .clipped()
    }
    
    private func resetSwipeState() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            swipeOffset = 0
            showActionButtons = false
        }
    }
    
    private func performDelete() {
        guard !isDeleting else { return }
        
        // Add haptic feedback
        let feedback = NSHapticFeedbackManager.defaultPerformer
        feedback.perform(.generic, performanceTime: .now)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isDeleting = true
            swipeOffset = -300 // Slide out completely
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDelete()
        }
    }
}

// Alternative simple version that responds to keyboard delete key
struct KeyboardDeleteableRow<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    @FocusState private var isFocused: Bool
    
    init(@ViewBuilder content: () -> Content, onDelete: @escaping () -> Void) {
        self.content = content()
        self.onDelete = onDelete
    }
    
    var body: some View {
        content
            .focusable()
            .focused($isFocused)
            .onDeleteCommand {
                onDelete()
            }
            .onTapGesture {
                isFocused = true
            }
    }
}
