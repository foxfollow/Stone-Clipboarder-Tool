//
//  QuickPickerWindowManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import SwiftUI
import AppKit

@MainActor
class QuickPickerWindowManager: NSObject, ObservableObject, QuickPickerDelegate {
    private var window: NSPanel?
    private weak var cbViewModel: CBViewModel?
    private var eventMonitor: Any?
    
    func setCBViewModel(_ viewModel: CBViewModel) {
        self.cbViewModel = viewModel
    }
    
    func showQuickPicker() {
        // If already visible, just return
        if window?.isVisible == true {
            return
        }
        
        guard let cbViewModel = cbViewModel else {
            print("CBViewModel is nil")
            return
        }
        
        // Create a panel (like Spotlight)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Create content view
        let contentView = QuickPickerView(viewModel: cbViewModel) { [weak self] in
            self?.hideQuickPicker()
        }
        
        panel.contentView = NSHostingView(rootView: contentView)
        
        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let origin = NSPoint(
                x: screenFrame.midX - 250,
                y: screenFrame.midY - 200
            )
            panel.setFrameOrigin(origin)
        }
        
        // Show the panel
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
        
        // Setup click-outside monitoring
        setupEventMonitoring()
    }
    
    func hideQuickPicker() {
        removeEventMonitoring()
        
        if let window = window {
            window.orderOut(nil)
            window.close()
        }
        
        self.window = nil
    }
    
    func isQuickPickerVisible() -> Bool {
        return window?.isVisible == true
    }
    
    private func setupEventMonitoring() {
        removeEventMonitoring()
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  window.isVisible else { return }
            
            let clickLocation = NSEvent.mouseLocation
            if !window.frame.contains(clickLocation) {
                self.hideQuickPicker()
            }
        }
    }
    
    private func removeEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    deinit {
        // Clean up on deinit
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
