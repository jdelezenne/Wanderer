import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section("Map") {
                Picker("Style", selection: $settings.mapStyleOption) {
                    ForEach(AppSettings.MapStyleOption.allCases, id: \.self) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)

            }

            Section("Units") {
                Picker("Distance", selection: $settings.useImperial) {
                    Text("Metric (km, m)").tag(false)
                    Text("Imperial (mi, ft)").tag(true)
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("Settings")
    }
}
