//
//  QPWindowKeyObserver.swift
//  StoneClipboarderTool
//
//  Reports whether the window hosting it is the key window, so the Quick
//  Picker can tell when typing no longer reaches it.
//

import AppKit
import SwiftUI

struct QPWindowKeyObserver: NSViewRepresentable {
    @Binding var isKey: Bool

    func makeNSView(context _: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = { isKey = $0 }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context _: Context) {
        nsView.onChange = { isKey = $0 }
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            guard let window else { return }
            onChange?(window.isKeyWindow)
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
