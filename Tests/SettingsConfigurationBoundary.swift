import Foundation
// Host-only appearance/authorization dependencies. The production SettingsViewModel and
// ConfigurationSaveController run unchanged; no system settings or App Group are accessed.
enum AppAppearance { case system, light, dark }
final class AppearanceController {
    static let shared = AppearanceController()
    var appearance = AppAppearance.system
    func setAppearance(_ value: AppAppearance) { appearance = value }
}
enum AuthorizationStatus { case notDetermined, denied, approved }
protocol ScreenTimeAuthorizationServiceProtocol { var authorizationStatus: AuthorizationStatus { get } }
final class ScreenTimeAuthorizationService: ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus = AuthorizationStatus.approved
}
extension AppGroupStorage { func loadActiveCycleSnapshot() -> CycleSnapshot? { runtime.snapshot } }
