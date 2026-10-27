//
//  BreakLoopColors.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI
import UIKit

// MARK: - Dynamic Color Helper
extension Color {
    static func blDynamic(lightHex: String, darkHex: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var str = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: str).scanHexInt64(&int)
        let r, g, b, a: Double
        switch str.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = Double((int >> 24) & 0xFF) / 255.0
            g = Double((int >> 16) & 0xFF) / 255.0
            b = Double((int >> 8) & 0xFF) / 255.0
            a = Double(int & 0xFF) / 255.0
        default:
            r = 1.0; g = 1.0; b = 1.0; a = 1.0
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Semantic Color Tokens
enum BLColor {
    // Canvas & Surface Tokens
    static let background = Color.blDynamic(lightHex: "#F8F9FC", darkHex: "#0C0E14")
    static let surface = Color.blDynamic(lightHex: "#FFFFFF", darkHex: "#161922")
    static let surfaceSubtle = Color.blDynamic(lightHex: "#EEF1F8", darkHex: "#212533")
    static let surfaceElevated = Color.blDynamic(lightHex: "#F3F3FD", darkHex: "#282A31")

    // Text & Content Tokens
    static let textPrimary = Color.blDynamic(lightHex: "#12141A", darkHex: "#F5F6FA")
    static let textSecondary = Color.blDynamic(lightHex: "#61687B", darkHex: "#9BA3B8")
    static let textTertiary = Color.blDynamic(lightHex: "#8E95A8", darkHex: "#61687B")

    // Brand Tokens
    static let brandPrimary = Color.blDynamic(lightHex: "#434EE8", darkHex: "#BEC2FF")
    static let brandInteractive = Color(uiColor: UIColor(hex: "#434EE8"))
    static let brandDeep = Color.blDynamic(lightHex: "#262E9B", darkHex: "#262E9B")
    static let brandSecondary = Color.blDynamic(lightHex: "#7B88D6", darkHex: "#9BA6E2")
    static let brandSoft = Color.blDynamic(lightHex: "#D6DCFB", darkHex: "#2B315A")

    // Structural & Semantic States
    static let divider = Color.blDynamic(lightHex: "#E4E7F0", darkHex: "#262A38")
    static let statusBreak = Color.blDynamic(lightHex: "#5E6AD2", darkHex: "#7B88D6")
    static let statusDeepFocus = Color.blDynamic(lightHex: "#3843C7", darkHex: "#5E6AD2")
    static let destructive = Color.blDynamic(lightHex: "#BA1A1A", darkHex: "#FFB4AB")

    // Card & Control Borders
    static let cardBorder = Color.blDynamic(lightHex: "#E4E7F0CC", darkHex: "#FFFFFF0F") // light: 80% alpha, dark: 6% alpha

    // Secondary Button Interactive States
    static let secondaryButtonBackground = Color.blDynamic(lightHex: "#434EE814", darkHex: "#434EE82E") // light 8%, dark 18%
    static let secondaryButtonForeground = Color.blDynamic(lightHex: "#434EE8", darkHex: "#9BA6E2")
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

