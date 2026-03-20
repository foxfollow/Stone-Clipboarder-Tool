//
//  DeleteButtonView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI

struct DeleteButtonView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    let item: CBItem
    @Binding var selectedItem: CBItem?

    var body: some View {
        Button(action: {
            if selectedItem?.id == item.id {
                selectedItem = nil
            }
            cbViewModel.deleteItem(item)
        }) {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
    }
}
