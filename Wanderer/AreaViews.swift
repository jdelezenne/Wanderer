import SwiftUI

struct AreaListView: View {
    let areaStore: AreaStore
    @State private var sortOrder = SortOrder.discovered

    enum SortOrder: String, CaseIterable {
        case discovered = "Discovered"
        case recent     = "Recent"
        case mostVisited = "Most Visited"
    }

    private var sortedAreas: [VisitedArea] {
        switch sortOrder {
        case .discovered:  return areaStore.areas.sorted { $0.firstVisitDate > $1.firstVisitDate }
        case .recent:      return areaStore.areas.sorted { $0.lastVisitDate > $1.lastVisitDate }
        case .mostVisited: return areaStore.areas.sorted { $0.visitCount > $1.visitCount }
        }
    }

    var body: some View {
        List {
            if !areaStore.areas.isEmpty {
                Section {
                    HStack(spacing: 0) {
                        areaStatCell("\(areaStore.areas.count)", "Areas")
                        Divider().frame(height: 28)
                        areaStatCell("\(areaStore.areas.reduce(0) { $0 + $1.visitCount })", "Visits")
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    ForEach(sortedAreas) { area in
                        AreaRow(area: area)
                    }
                } header: {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 4)
                }
            }
        }
        .navigationTitle("Areas")
        .overlay {
            if areaStore.areas.isEmpty {
                ContentUnavailableView(
                    "No Areas Discovered",
                    systemImage: "map",
                    description: Text("Walk around to discover neighborhoods.")
                )
            }
        }
    }

    private func areaStatCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AreaRow: View {
    let area: VisitedArea

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(area.name).font(.body)
                Text("Discovered \(area.firstVisitDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(area.visitCount)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
                Text("visits")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
