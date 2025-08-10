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

    var body: some View {
        Button(action: {
            cbViewModel.deleteItem(item)
        }) {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
    }
}
