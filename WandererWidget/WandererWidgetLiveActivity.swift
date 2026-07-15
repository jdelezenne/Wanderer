import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivityLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Label("\(context.state.stepCount)", systemImage: "shoeprints.fill")
                    .font(.headline.monospacedDigit())
                Text("Steps").font(.caption2).foregroundStyle(.secondary)
            }

            Divider().frame(height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Label(Formatters.duration(context.state.elapsedSeconds), systemImage: "timer")
                    .font(.headline.monospacedDigit())
                Text("Time").font(.caption2).foregroundStyle(.secondary)
            }

            Divider().frame(height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Label(Formatters.distance(context.state.distanceMeters), systemImage: "figure.walk")
                    .font(.headline.monospacedDigit())
                Text("Distance").font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.walk.circle.fill")
                .font(.title)
                .foregroundStyle(context.state.isPaused ? .orange : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct WandererWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.stepCount)", systemImage: "shoeprints.fill")
                        .font(.headline.monospacedDigit())
                        .labelStyle(.titleAndIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(Formatters.duration(context.state.elapsedSeconds), systemImage: "timer")
                        .font(.headline.monospacedDigit())
                        .labelStyle(.titleAndIcon)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(Formatters.distance(context.state.distanceMeters))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.state.isPaused {
                            Label("Paused", systemImage: "pause.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        } else {
                            Label("Tracking", systemImage: "figure.walk")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } compactLeading: {
                Label("\(context.state.stepCount)", systemImage: "shoeprints.fill")
                    .font(.caption2.monospacedDigit())
                    .labelStyle(.titleOnly)
            } compactTrailing: {
                Text(Formatters.duration(context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.walk.circle.fill")
                    .foregroundStyle(context.state.isPaused ? .orange : .green)
            }
            .keylineTint(.green)
        }
    }
}

#Preview("Lock Screen", as: .content, using: TripActivityAttributes(startDate: .now)) {
    WandererWidgetLiveActivity()
} contentStates: {
    TripActivityAttributes.ContentState(stepCount: 1240, elapsedSeconds: 892, distanceMeters: 980, isPaused: false)
    TripActivityAttributes.ContentState(stepCount: 1240, elapsedSeconds: 900, distanceMeters: 980, isPaused: true)
}
