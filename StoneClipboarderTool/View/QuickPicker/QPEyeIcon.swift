//
//  QPEyeIcon.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The show / hide eye of Passwords rows and the ⌥E editor: full contrast on
/// a round backing, accent-colored while the content is shown.
struct QPEyeIcon: View {
    let isRevealed: Bool
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isRevealed ? Color.white : Color.primary)
            .frame(width: size + 16, height: size + 16)
            .background(
                Circle()
                    .fill(isRevealed ? Color.accentColor : Color.primary.opacity(0.14))
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(isRevealed ? 0 : 0.25), lineWidth: 1)
            )
            .contentShape(Circle())
    }
}
