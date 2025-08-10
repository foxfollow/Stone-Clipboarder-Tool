//
//  SettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: $settingsManager.showInMenubar)
                    .help("Show clipboard history in the menu bar for quick access")
                
                Toggle("Show Main Window", isOn: $settingsManager.showMainWindow)
                    .help("Keep the main window visible in the dock")
            }
            
            Section("About") {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text("StoneClipboarderTool")
                            .font(.headline)
                        Text("Clipboard History Manager")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(width: 400, height: 300)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
