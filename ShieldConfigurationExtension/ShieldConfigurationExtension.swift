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
        formatter.timeStyle = .short
        let title: String
        let subtitle: String
        let asset: String
        if let session = runtime?.deepFocus, session.endsAt > now {
            title = "Protect your focus."
            subtitle = "Selected apps are paused until \(formatter.string(from: session.endsAt))."
            asset = "BLShieldHorizonDeepFocus"
        } else if let deadline = runtime?.cooldown, deadline.endsAt > now {
            title = "A little space."
            subtitle = "Your selected apps are paused until \(formatter.string(from: deadline.endsAt))."
            asset = "BLShieldHorizonCooldown"
        } else {
            title = "A moment away."
            subtitle = "This app is temporarily unavailable."
            asset = "BLShieldHorizonFallback"
        }
        let brand = UIColor(red: 67/255, green: 78/255, blue: 232/255, alpha: 1)
        let icon = UIImage(named: asset, in: Bundle(for: ShieldConfigurationExtension.self), compatibleWith: nil)
            ?? UIImage(systemName: "pause.circle.fill")?.withTintColor(brand, renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: UIColor(red: 12/255, green: 14/255, blue: 20/255, alpha: 1),
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: UIColor(red: 245/255, green: 246/255, blue: 250/255, alpha: 1)),
            subtitle: ShieldConfiguration.Label(text: subtitle,
                color: UIColor(red: 184/255, green: 193/255, blue: 217/255, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close App", color: .white),
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
