//
//  EditingButtonView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI

struct EditingButtonView: View {
    @Binding var editingMode: Bool
    
    var body: some View {
        Button {
            editingMode.toggle()
        } label: {
            Label("Edit mode", systemImage: "pencil")
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(editingMode ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 2)
                    
                )
        }
    }
}
