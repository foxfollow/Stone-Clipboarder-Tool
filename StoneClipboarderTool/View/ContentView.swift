//
//  ContentView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//
#if DEBUG
import SwiftData
#endif
import SwiftUI
import Combine
import Sparkle

enum ClipboardTab: String, CaseIterable, Identifiable {
    case recent
    case favorites

    var id: Self { self }

    var title: String {
        return self.rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .recent: "clock"
        case .favorites: "star"
        }
    }
}


struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    @EnvironmentObject var cbViewModel: CBViewModel
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var hotkeyManager: HotkeyManager

    @State private var editingMode: Bool = false
    @State private var showingDeleteAllAlert = false
    @State private var selectedItem: CBItem? = nil
    @State private var selectedTab: ClipboardTab = .recent
    @State private var searchText: String = ""



    // Filtered items based on search text
    private var filteredRecentItems: [CBItem] {
        if searchText.isEmpty {
            return cbViewModel.items
        }
        return cbViewModel.items.filter { item in
            matchesSearch(item: item)
        }
    }

    private var filteredFavoriteItems: [CBItem] {
        if searchText.isEmpty {
            return cbViewModel.favoriteItems
        }
        return cbViewModel.favoriteItems.filter { item in
            matchesSearch(item: item)
        }
    }

    private func matchesSearch(item: CBItem) -> Bool {
        let lowercasedSearch = searchText.lowercased()

        // Search in text content
        if let content = item.content,
           content.lowercased().contains(lowercasedSearch) {
            return true
        }

        // Search in file name
        if let fileName = item.fileName,
           fileName.lowercased().contains(lowercasedSearch) {
            return true
        }

        return false
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Tab picker
                ClipboardHeader(selectedTab: $selectedTab, searchText: $searchText)
                

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

            if filteredRecentItems.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No items match '\(searchText)'")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRecentItems) { item in
                    DetailedCardView(
                        editingMode: $editingMode,
                        selectedItem: $selectedItem,
                        item: item
                    )
                    .onAppear {
                        cbViewModel.markItemAccessed(item)
                        // Only trigger load more if not searching and this is the last item
                        if searchText.isEmpty && item == cbViewModel.items.last {
                            cbViewModel.loadMoreItems()
                        }
                    }
                }
                .onDelete(perform: deleteItems)

                // Only show loading indicator when not searching
                if cbViewModel.isLoadingMore && searchText.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading more...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.2), value: filteredRecentItems.count)
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
            } else if filteredFavoriteItems.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No favorite items match '\(searchText)'")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredFavoriteItems) { item in
                    DetailedCardView(
                        editingMode: $editingMode,
                        selectedItem: $selectedItem,
                        item: item,
                        showFavoriteControls: true
                    )
                    .onAppear {
                        cbViewModel.markItemAccessed(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.3), value: filteredFavoriteItems.count)
    }

    private func addItem(content: String? = nil) {
        withAnimation(.easeInOut(duration: 0.3)) {
            cbViewModel.addItem(content: content ?? "New item content")
        }
    }

    private func deleteAllItems() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cbViewModel.deleteAllItems()
            editingMode = false
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation(.easeInOut(duration: 0.3)) {
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

//#Preview {
//    let schema = Schema([CBItem.self])
//    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//    let container = try! ModelContainer(for: schema, configurations: [configuration])
//    let viewModel = CBViewModel()
//    let settingsManager = SettingsManager()
//    let hotkeyManager = HotkeyManager()
//
//    return ContentView()
//        //updater: nil)
//        .environmentObject(viewModel)
//        .environmentObject(settingsManager)
//        .environmentObject(hotkeyManager)
//        .modelContainer(container)
//        .onAppear {
//            viewModel.setModelContext(container.mainContext)
//        }
//}

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
                    .transition(.scale.combined(with: .opacity))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedItem = item
                }
            } label: {
                BarNavigationCellView(item: item)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedItem?.id == item.id ? Color.blue.opacity(0.2) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: selectedItem?.id == item.id)
            )

            Spacer()

            // Favorite button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    cbViewModel.toggleFavorite(item)
                }
            }) {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isFavorite ? .red : .secondary)
                    .scaleEffect(item.isFavorite ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isFavorite)
            }
            .buttonStyle(.plain)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .animation(.easeInOut(duration: 0.2), value: editingMode)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CBItem.self, configurations: config)
    let viewModel = CBViewModel()
    let settingsManager = SettingsManager()
    let hotkeyManager = HotkeyManager()

    ContentView()
        .environmentObject(viewModel)
        .environmentObject(settingsManager)
        .environmentObject(hotkeyManager)
        .modelContainer(container)
        .onAppear {
            viewModel.setModelContext(container.mainContext)
            viewModel.setSettingsManager(settingsManager)
        }
}


import SwiftUI

struct ClipboardHeader: View {

    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 8) {
            // Segmented control with liquid glass effect (macOS 26+)
            if #available(macOS 26.0, *) {
                Picker("", selection: $selectedTab) {
                    ForEach(ClipboardTab.allCases, id: \.self) { tab in
                        Text(tab.title)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .glassEffect(.regular)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onChange(of: selectedTab) { oldValue, newValue in
                    searchText = ""
                }
            } else {
                // Fallback for macOS 15.0 - 25.x
                Picker("", selection: $selectedTab) {
                    ForEach(ClipboardTab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onChange(of: selectedTab) { oldValue, newValue in
                    searchText = ""
                }
            }

            // Search bar with consistent styling
            SearchBarView(searchText: $searchText)
        }
    }
}
