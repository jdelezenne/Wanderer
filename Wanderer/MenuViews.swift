import SwiftUI

struct AppMenuView: View {
    let tripStore: TripStore
    let collectionStore: CollectionStore
    let areaStore: AreaStore
    let fogStore: FogStore
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            NavigationLink {
                AccountView(tripStore: tripStore, collectionStore: collectionStore, fogStore: fogStore)
            } label: {
                Label("Account", systemImage: "person.circle")
            }

            NavigationLink {
                DailyStatsView(tripStore: tripStore)
            } label: {
                Label("Activity", systemImage: "calendar")
            }

            NavigationLink {
                AreaListView(areaStore: areaStore)
            } label: {
                Label("Areas", systemImage: "map")
            }

            NavigationLink {
                CollectionView(collectionStore: collectionStore)
            } label: {
                Label("Collection", systemImage: "sparkles")
            }

            NavigationLink {
                TripHistoryView(tripStore: tripStore)
            } label: {
                Label("Trip History", systemImage: "clock.arrow.circlepath")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gear")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All Trips", systemImage: "trash")
                }
                .disabled(tripStore.trips.isEmpty)
            }
        }
        .navigationTitle("Wanderer")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete all trips?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { tripStore.deleteAll() }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct CollectionView: View {
    let collectionStore: CollectionStore

    var body: some View {
        let grouped = Dictionary(grouping: collectionStore.items, by: \.kind)
        List {
            ForEach(NearbyPlaceKind.allCases, id: \.rawValue) { kind in
                if let kindItems = grouped[kind], !kindItems.isEmpty {
                    Section(kind.label) {
                        ForEach(kindItems) { item in
                            HStack(spacing: 12) {
                                Image(uiImage: kind.spriteImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .background(kind.color, in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.body)
                                    Text(item.collectedDate, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Collection")
        .overlay {
            if collectionStore.items.isEmpty {
                ContentUnavailableView(
                    "Nothing Collected Yet",
                    systemImage: "sparkles",
                    description: Text("Explore in AR view to collect nearby places.")
                )
            }
        }
    }
}
