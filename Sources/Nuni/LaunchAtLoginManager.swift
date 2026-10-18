import AppKit
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusText = "Checking login item status…"

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func setEnabled(_ shouldEnable: Bool) {
        do {
            if shouldEnable {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh(errorMessage: error.localizedDescription)
        }
    }

    func refresh() {
        refresh(errorMessage: nil)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refresh(errorMessage: String?) {
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval

        if let errorMessage {
            statusText = "Could not update the login item: \(errorMessage)"
            return
        }

        switch status {
        case .enabled:
            statusText = "Nuni will open automatically when you log in."
        case .requiresApproval:
            statusText = "macOS is waiting for approval in Login Items."
        case .notRegistered:
            statusText = "Nuni will stay closed when you log in."
        case .notFound:
            statusText = "Move Nuni to Applications, then try again."
        @unknown default:
            statusText = "Login item status is unavailable."
        }
    }
}
