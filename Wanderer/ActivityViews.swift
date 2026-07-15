import SwiftUI

struct DayStats {
    let date: Date
    let trips: [TripRecap]

    var totalSteps: Int { trips.reduce(0) { $0 + $1.steps } }
    var totalDistanceMeters: Double { trips.reduce(0) { $0 + $1.distanceMeters } }
    var totalElapsedSeconds: TimeInterval { trips.reduce(0) { $0 + $1.elapsedSeconds } }

    func formattedDistance(imperial: Bool = false) -> String { Formatters.distance(totalDistanceMeters, imperial: imperial) }
    var formattedDuration: String { Formatters.duration(totalElapsedSeconds) }
}

struct DailyStatsView: View {
    let tripStore: TripStore
    @Environment(AppSettings.self) private var settings
    @State private var monthOffset = 0
    @State private var selectedDay: Date? = nil
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { monthOffset -= 1 } label: {
                    Image(systemName: "chevron.left").padding(8)
                }
                Spacer()
                Text(displayMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button { monthOffset += 1 } label: {
                    Image(systemName: "chevron.right").padding(8)
                }
                .disabled(monthOffset >= 0)
            }
            .padding(.horizontal)

            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .frame(maxWidth: .infinity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<leadingOffset, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(daysInMonth, id: \.self) { date in
                    let ds = dayStats(for: date)
                    let isSel = selectedDay.map { cal.isDate($0, inSameDayAs: date) } ?? false
                    let isFuture = date > cal.startOfDay(for: .now)
                    DayCell(
                        day: cal.component(.day, from: date),
                        hasActivity: ds != nil,
                        isSelected: isSel,
                        isToday: cal.isDateInToday(date),
                        isFuture: isFuture
                    )
                    .onTapGesture { if !isFuture { selectedDay = isSel ? nil : date } }
                }
            }
            .padding(.horizontal)

            Divider().padding(.vertical, 10)

            if let day = selectedDay {
                if let ds = dayStats(for: day) {
                    DayDetailView(stats: ds)
                } else {
                    VStack(spacing: 8) {
                        Text(day, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ContentUnavailableView(
                            "No Activity",
                            systemImage: "figure.stand",
                            description: Text("No trips recorded on this day.")
                        )
                    }
                    .padding(.top, 4)
                }
            } else {
                monthSummaryView
            }
        }
        .navigationTitle("Activity")
    }

    private var displayMonth: Date {
        let base = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        return cal.date(byAdding: .month, value: monthOffset, to: base)!
    }

    private var daysInMonth: [Date] {
        guard let range = cal.range(of: .day, in: .month, for: displayMonth) else { return [] }
        return range.map { cal.date(byAdding: .day, value: $0 - 1, to: displayMonth)! }
    }

    private var leadingOffset: Int {
        guard let first = daysInMonth.first else { return 0 }
        return (cal.component(.weekday, from: first) - 1 + 7) % 7
    }

    private func dayStats(for date: Date) -> DayStats? {
        let dayTrips = tripStore.trips.filter { cal.isDate($0.startDate, inSameDayAs: date) }
        return dayTrips.isEmpty ? nil : DayStats(date: date, trips: dayTrips)
    }

    private var monthSummaryView: some View {
        let all = daysInMonth.compactMap { dayStats(for: $0) }
        let steps = all.reduce(0) { $0 + $1.totalSteps }
        let dist  = all.reduce(0) { $0 + $1.totalDistanceMeters }
        let time  = all.reduce(0) { $0 + $1.totalElapsedSeconds }
        return VStack(spacing: 8) {
            Text("Month Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                summaryCell("\(steps)", "Steps")
                Divider().frame(height: 28)
                summaryCell(Formatters.distance(dist, imperial: settings.useImperial), "Distance")
                Divider().frame(height: 28)
                summaryCell(Formatters.duration(time), "Time")
                Divider().frame(height: 28)
                summaryCell("\(all.count)", "Active Days")
            }
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
        }
        .padding(.top, 4)
    }

    private func summaryCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DayCell: View {
    let day: Int
    let hasActivity: Bool
    let isSelected: Bool
    let isToday: Bool
    var isFuture: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    isSelected ? Color.blue : hasActivity ? Color.blue.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isFuture ? Color.secondary.opacity(0.4) : isSelected ? .white : isToday ? Color.blue : .primary)
            Circle()
                .fill(isSelected ? Color.white : Color.blue)
                .frame(width: 4, height: 4)
                .opacity(hasActivity ? 1 : 0)
        }
    }
}

struct DayDetailView: View {
    let stats: DayStats
    @Environment(AppSettings.self) private var settings
    @State private var selectedTrip: TripRecap?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(stats.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    detailCell("\(stats.totalSteps)", "Steps")
                    Divider().frame(height: 28)
                    detailCell(stats.formattedDistance(imperial: settings.useImperial), "Distance")
                    Divider().frame(height: 28)
                    detailCell(stats.formattedDuration, "Time")
                    Divider().frame(height: 28)
                    detailCell("\(stats.trips.count)", stats.trips.count == 1 ? "Trip" : "Trips")
                }
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                ForEach(stats.trips) { trip in
                    Button { selectedTrip = trip } label: {
                        TripHistoryRow(trip: trip)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $selectedTrip) { recap in
            TripRecapView(recap: recap)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func detailCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
