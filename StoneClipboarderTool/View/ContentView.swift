//
//  ContentView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftData
import SwiftUI
import Combine
import Sparkle

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    @EnvironmentObject var cbViewModel: CBViewModel
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var hotkeyManager: HotkeyManager

    @State private var editingMode: Bool = false
    @State private var showingDeleteAllAlert = false
    @State private var selectedItem: CBItem? = nil
    @State private var selectedTab: ClipboardTab = .recent

    enum ClipboardTab: CaseIterable {
        case recent, favorites

        var title: String {
            switch self {
            case .recent: return "Recent"
            case .favorites: return "Favorites"
            }
        }

        var icon: String {
            switch self {
            case .recent: return "clock"
            case .favorites: return "heart"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(ClipboardTab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .recent:
                        recentItemsList
                    case .favorites:
                        favoritesItemsList
                    }
                }
            }
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 230
            )
            .navigationTitle("Clipboard History")
            .toolbar {
                ToolbarItem(id: "edit", placement: .secondaryAction) {
                    EditingButtonView(editingMode: $editingMode)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        openWindow(id: "settings")
                    }) {
                        Label("Settings", systemImage: "gear")
                    }

                    Button(action: {
                        addItem()
                    }) {
                        Label("Add Item", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .status) {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Monitoring clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Delete All Clipboard History", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    deleteAllItems()
                }
            } message: {
                Text(
                    "This will permanently delete all clipboard history items. This action cannot be undone."
                )
            }
        } detail: {
            if let selectedItem = selectedItem {
                ZoomableDetailView(item: selectedItem)
                    .environmentObject(cbViewModel)
            } else {
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SelectClipboardItem"))) {
            notification in
            if let itemUUID = notification.object as? String,
                let item = cbViewModel.items.first(where: { "\($0.id)" == itemUUID })
            {
                selectedItem = item
            }
        }
        .onAppear {
            setupWindowBehavior()
        }
    }

    @ViewBuilder
    private var recentItemsList: some View {
        List {
            if editingMode {
                Button("Delete All", role: .destructive) {
                    showingDeleteAllAlert = true
                }
                .foregroundStyle(.red)
            }
            ForEach(cbViewModel.items) { item in
                DetailedCardView(
                    editingMode: $editingMode,
                    selectedItem: $selectedItem,
                    item: item
                )
                .onAppear {
                    if item == cbViewModel.items.last {
                        cbViewModel.loadMoreItems()
                    }
                }
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var favoritesItemsList: some View {
        List {
            if cbViewModel.favoriteItems.isEmpty {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "heart")
                } description: {
                    Text("Tap the heart icon on items to add them to favorites")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(cbViewModel.favoriteItems) { item in
                    DetailedCardView(
                        editingMode: $editingMode,
                        selectedItem: $selectedItem,
                        item: item,
                        showFavoriteControls: true)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func addItem(content: String? = nil) {
        withAnimation {
            cbViewModel.addItem(content: content ?? "New item content")
        }
    }

    private func deleteAllItems() {
        withAnimation {
            cbViewModel.deleteAllItems()
            editingMode = false
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            cbViewModel.deleteItems(at: offsets, from: cbViewModel.items)
        }
    }

    private func setupWindowBehavior() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.title == "Clipboard History" }) {
                // Set window behavior to automatically move to active space
                window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

                // Set up workspace observer to move window when user changes desktops
                NotificationCenter.default.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    // Force window to follow to new desktop if it's visible and main window is shown
                    if settingsManager.showMainWindow && window.isVisible {
                        // Temporarily hide and show to force move to current space
                        window.orderOut(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([CBItem.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let viewModel = CBViewModel()
    let settingsManager = SettingsManager()
    let hotkeyManager = HotkeyManager()

    return ContentView()
        //updater: nil)
        .environmentObject(viewModel)
        .environmentObject(settingsManager)
        .environmentObject(hotkeyManager)
        .modelContainer(container)
        .onAppear {
            viewModel.setModelContext(container.mainContext)
        }
}

struct DetailedCardView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    @Binding var editingMode: Bool
    @Binding var selectedItem: CBItem?
    var item: CBItem
    var showFavoriteControls: Bool = false

    var body: some View {
        HStack {
            if editingMode {
                DeleteButtonView(item: item)
            }

            Button {
                selectedItem = item
            } label: {
                BarNavigationCellView(item: item)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedItem?.id == item.id ? Color.blue.opacity(0.2) : Color.clear)
            )

            Spacer()

            // Favorite button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    cbViewModel.toggleFavorite(item)
                }
            }) {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isFavorite ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }
}
