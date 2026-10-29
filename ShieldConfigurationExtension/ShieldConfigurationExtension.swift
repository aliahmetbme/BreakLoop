//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let storage = AppGroupStorage()

    private func makeShieldConfiguration() -> ShieldConfiguration {
        defer { _ = PersistentLogStore.shared.flush(timeout: 0.03) }
        AppLogger.shared.record("shield_presented", category: .shield, outcome: "observed")
        let now = Date()
        // Read one authoritative generation; an unreadable record uses the safe fallback.
        let runtime = try? storage.readRuntime()
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        let title: String
        let subtitle: String
        let asset: String
        let backdrop: UIColor
        if let session = runtime?.deepFocus, session.endsAt > now {
            title = String(localized: "Protect your focus.", bundle: Bundle(for: ShieldConfigurationExtension.self))
            subtitle = String(localized: "shield.focusUntil", defaultValue: "Selected apps are paused until \(formatter.string(from: session.endsAt)).", bundle: Bundle(for: ShieldConfigurationExtension.self))
            asset = "BLShieldHorizonDeepFocus"
            backdrop = UIColor(red: 24/255, green: 32/255, blue: 61/255, alpha: 1)
        } else if let deadline = runtime?.cooldown, deadline.endsAt > now {
            title = String(localized: "A little space.", bundle: Bundle(for: ShieldConfigurationExtension.self))
            subtitle = String(localized: "shield.cooldownUntil", defaultValue: "Your selected apps are paused until \(formatter.string(from: deadline.endsAt)).", bundle: Bundle(for: ShieldConfigurationExtension.self))
            asset = "BLShieldHorizonCooldown"
            backdrop = UIColor(red: 48/255, green: 38/255, blue: 62/255, alpha: 1)
        } else {
            title = String(localized: "A moment away.", bundle: Bundle(for: ShieldConfigurationExtension.self))
            subtitle = String(localized: "This app is temporarily unavailable.", bundle: Bundle(for: ShieldConfigurationExtension.self))
            asset = "BLShieldHorizonFallback"
            backdrop = UIColor(red: 34/255, green: 41/255, blue: 57/255, alpha: 1)
        }
        let brand = UIColor(red: 67/255, green: 78/255, blue: 232/255, alpha: 1)
        let icon = UIImage(named: asset, in: Bundle(for: ShieldConfigurationExtension.self), compatibleWith: nil)
            ?? UIImage(systemName: "pause.circle.fill")?.withTintColor(brand, renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            // The whole system background uses the current state's static horizon
            // palette; the artwork stays inside Apple's icon area.
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: backdrop,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: UIColor(red: 245/255, green: 246/255, blue: 250/255, alpha: 1)),
            subtitle: ShieldConfiguration.Label(text: subtitle,
                color: UIColor(red: 184/255, green: 193/255, blue: 217/255, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: String(localized: "Close App", bundle: Bundle(for: ShieldConfigurationExtension.self)), color: .white),
            primaryButtonBackgroundColor: brand
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeShieldConfiguration()
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeShieldConfiguration()
    }
}
