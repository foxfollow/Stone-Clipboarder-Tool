//
//  ClipboardAlerts.swift
//  StoneClipboarderTool
//
//  Created by Claude on 20.03.2026.
//

import SwiftUI

enum ClipboardAlert: Identifiable {
    case cleanup
    case deleteAll

    var id: String {
        switch self {
        case .cleanup: return "cleanup"
        case .deleteAll: return "deleteAll"
        }
    }
}

struct ClipboardAlertModifier: ViewModifier {
    @Binding var activeAlert: ClipboardAlert?
    var onCleanup: () -> Void
    var onDeleteAll: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { activeAlert != nil },
                    set: { if !$0 { activeAlert = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {}
                switch activeAlert {
                case .cleanup:
                    Button("Clean Up", role: .destructive) {
                        onCleanup()
                    }
                case .deleteAll:
                    Button("Delete All", role: .destructive) {
                        onDeleteAll()
                    }
                case nil:
                    EmptyView()
                }
            } message: {
                Text(alertMessage)
            }
    }

    private var alertTitle: String {
        switch activeAlert {
        case .cleanup:
            return "Clean Up Clipboard History"
        case .deleteAll:
            return "Delete All Clipboard History"
        case nil:
            return ""
        }
    }

    private var alertMessage: String {
        switch activeAlert {
        case .cleanup:
            return "This will remove old items beyond the maximum limit and free up memory. Favorites will be preserved."
        case .deleteAll:
            return "This will permanently delete all clipboard history items. This action cannot be undone."
        case nil:
            return ""
        }
    }
}

extension View {
    func clipboardAlert(
        _ activeAlert: Binding<ClipboardAlert?>,
        onCleanup: @escaping () -> Void,
        onDeleteAll: @escaping () -> Void
    ) -> some View {
        modifier(ClipboardAlertModifier(
            activeAlert: activeAlert,
            onCleanup: onCleanup,
            onDeleteAll: onDeleteAll
        ))
    }
}
