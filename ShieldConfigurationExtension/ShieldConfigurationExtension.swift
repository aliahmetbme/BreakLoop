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
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if let deepFocus = storage.loadDeepFocusSession(), deepFocus.isActive {
            let endTimeString = formatter.string(from: deepFocus.endsAt)
            return ShieldConfiguration(
                backgroundBlurStyle: .systemThickMaterialDark,
                backgroundColor: UIColor(red: 0.08, green: 0.07, blue: 0.12, alpha: 0.95),
                icon: UIImage(systemName: "flame.fill")?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal),
                title: ShieldConfiguration.Label(
                    text: "Deep Focus Active",
                    color: .white
                ),
                subtitle: ShieldConfiguration.Label(
                    text: "Selected apps are blocked until \(endTimeString). Stay in the flow.",
                    color: UIColor(white: 0.8, alpha: 1.0)
                ),
                primaryButtonLabel: ShieldConfiguration.Label(
                    text: "Stay Focused",
                    color: .white
                ),
                primaryButtonBackgroundColor: UIColor.systemOrange
            )
        }

        if let cooldownEnd = try? storage.loadCooldownEndDate() {
            let endTimeString = formatter.string(from: cooldownEnd)
            return ShieldConfiguration(
                backgroundBlurStyle: .systemThickMaterialDark,
                backgroundColor: UIColor(red: 0.07, green: 0.08, blue: 0.14, alpha: 0.95),
                icon: UIImage(systemName: "hourglass")?.withTintColor(.systemIndigo, renderingMode: .alwaysOriginal),
                title: ShieldConfiguration.Label(
                    text: "Break the loop.",
                    color: .white
                ),
                subtitle: ShieldConfiguration.Label(
                    text: "Your usage limit is complete. Take a short break until \(endTimeString).",
                    color: UIColor(white: 0.8, alpha: 1.0)
                ),
                primaryButtonLabel: ShieldConfiguration.Label(
                    text: "Take a Break",
                    color: .white
                ),
                primaryButtonBackgroundColor: UIColor.systemIndigo
            )
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.08, blue: 0.14, alpha: 0.95),
            icon: UIImage(systemName: "pause.circle.fill")?.withTintColor(.systemIndigo, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(
                text: "Break the loop.",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Your usage limit is complete. Take a short break before continuing.",
                color: UIColor(white: 0.8, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemIndigo
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
