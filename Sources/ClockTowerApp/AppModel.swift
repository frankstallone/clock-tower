import AppKit
import ClockTowerCore
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard canSave, settings != oldValue else { return }
            do { try store.save(settings) } catch {
                message = "Could not save Clock Tower settings: \(error.localizedDescription)"
            }
        }
    }
    @Published var now = Date()
    @Published var preview: Date?
    @Published var isAddingCity = false
    @Published var message: String?
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false

    private let store = SettingsStore()
    private var canSave = true

    init() {
        do { settings = try store.load() } catch {
            settings = .defaults
            canSave = false
            message = "Settings could not be loaded. Changes are temporary until you resolve this error and reopen Clock Tower: \(error.localizedDescription)"
        }
        refreshLogin()
    }

    func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "Could not change Open at Login: \(error.localizedDescription)"
        }
        refreshLogin()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
