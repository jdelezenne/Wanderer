import SwiftUI

struct AccountView: View {
    let tripStore: TripStore
    let collectionStore: CollectionStore
    let fogStore: FogStore
    @Environment(AppSettings.self) private var settings
    @FocusState private var nicknameFieldFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                profileHeader(nickname: $settings.nickname)
            }

            Section("All-Time Stats") {
                statRow("Total Trips", "\(tripStore.trips.count)", systemImage: "figure.walk")
                statRow("Total Distance", Formatters.distance(totalDistance, imperial: settings.useImperial),
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                statRow("Total Steps", totalSteps.formatted(), systemImage: "shoeprints.fill")
                statRow("Total Time", Formatters.duration(totalTime), systemImage: "timer")
                statRow("Active Days", "\(activeDays)", systemImage: "calendar")
                statRow("Places Collected", "\(collectionStore.items.count)", systemImage: "sparkles")
            }

            Section("Explored Area") {
                let area = fogStore.revealedAreaKm2
                statRow("Map Revealed",
                        area < 0.01 ? "—" : String(format: "%.2f km²", area),
                        systemImage: "map.fill")
            }

            if !personalRecords.isEmpty {
                Section("Personal Records") {
                    ForEach(personalRecords, id: \.label) { pr in
                        prRow(pr.label, pr.value, date: pr.date, systemImage: pr.icon)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Account")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nicknameFieldFocused = false }
            }
        }
    }

    // MARK: - Subviews

    private func profileHeader(nickname: Binding<String>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Explorer", text: nickname)
                        .font(.title2.bold())
                        .focused($nicknameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nicknameFieldFocused = false }

                    if !nicknameFieldFocused {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }

                Text(profileSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statRow(_ label: String, _ value: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func prRow(_ label: String, _ value: String, date: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                Text(date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed values

    private var totalDistance: Double { tripStore.trips.reduce(0) { $0 + $1.distanceMeters } }
    private var totalSteps: Int { tripStore.trips.reduce(0) { $0 + $1.steps } }
    private var totalTime: TimeInterval { tripStore.trips.reduce(0) { $0 + $1.elapsedSeconds } }

    private var activeDays: Int {
        let cal = Calendar.current
        return Set(tripStore.trips.map { cal.startOfDay(for: $0.startDate) }).count
    }

    private var profileSubtitle: String {
        guard !tripStore.trips.isEmpty else { return "No trips yet — start exploring!" }
        return "\(tripStore.trips.count) trip\(tripStore.trips.count == 1 ? "" : "s") · \(activeDays) active day\(activeDays == 1 ? "" : "s")"
    }

    private struct PersonalRecord {
        let label: String
        let value: String
        let date: String
        let icon: String
    }

    private var personalRecords: [PersonalRecord] {
        var records: [PersonalRecord] = []
        if let best = tripStore.trips.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            records.append(PersonalRecord(
                label: "Longest Trip",
                value: Formatters.distance(best.distanceMeters, imperial: settings.useImperial),
                date: best.formattedDate,
                icon: "trophy.fill"
            ))
        }
        if let best = tripStore.trips.max(by: { $0.steps < $1.steps }) {
            records.append(PersonalRecord(
                label: "Most Steps",
                value: best.steps.formatted(),
                date: best.formattedDate,
                icon: "shoeprints.fill"
            ))
        }
        if let best = tripStore.trips.filter({ $0.distanceMeters > 100 })
            .max(by: { $0.averageSpeedMetersPerSecond < $1.averageSpeedMetersPerSecond }) {
            records.append(PersonalRecord(
                label: "Fastest Pace",
                value: Formatters.speed(best.averageSpeedMetersPerSecond, imperial: settings.useImperial),
                date: best.formattedDate,
                icon: "speedometer"
            ))
        }
        if let best = tripStore.trips.max(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
            records.append(PersonalRecord(
                label: "Longest Duration",
                value: Formatters.duration(best.elapsedSeconds),
                date: best.formattedDate,
                icon: "timer"
            ))
        }
        return records
    }
}
