import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Clock display") {
                Toggle("Use 24-hour time", isOn: $model.settings.use24Hour)
                Toggle("Show date", isOn: $model.settings.showDate)
                Toggle(isOn: $model.settings.compact) {
                    Text("Compact view")
                    Text("Reduce row spacing and shorten names in the menu bar.")
                }
            }
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if model.loginNeedsApproval {
                    LabeledContent("Allow Clock Tower in Login Items.") {
                        Button("Open System Settings…") { model.openLoginSettings() }
                    }
                }
            }
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
