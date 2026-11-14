//
//  SettingsDetailContainer.swift
//  StoneClipboarderTool
//

import SwiftUI

struct SettingsDetailContainer<Content: View>: View {
    let subtitle: String
    /// A picked search result: scrolled to and highlighted.
    var highlight = SettingsHighlight()
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.settingsHighlightedAnchors, highlight.anchors)
                    .onChange(of: highlight.token) { _, _ in
                        scroll(proxy, to: highlight.scrollTargets)
                    }
                    .onAppear {
                        scroll(proxy, to: highlight.scrollTargets)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// After the page has rendered (a result may switch pages). A missing
    /// id is ignored, so the parent row stays in view when its child is hidden.
    private func scroll(_ proxy: ScrollViewProxy, to targets: [String]) {
        guard !targets.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                for target in targets {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }
}
