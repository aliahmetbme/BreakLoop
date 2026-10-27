//
//  BreakLoopTypography.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

enum BLTypography {
    // Dynamic Type Native Hierarchy
    static let largeTitle: Font = .largeTitle.weight(.bold)
    static let title: Font = .title2.weight(.bold)
    static let title2: Font = .title2.weight(.bold)
    static let title3: Font = .title3.weight(.semibold)
    static let headline: Font = .headline
    static let headlineBold: Font = .headline.weight(.bold)
    static let body: Font = .body
    static let bodyMedium: Font = .body.weight(.medium)
    static let secondary: Font = .subheadline
    static let secondaryMedium: Font = .subheadline.weight(.medium)
    static let secondarySemibold: Font = .subheadline.weight(.semibold)
    static let callout: Font = .callout
    static let footnote: Font = .footnote
    static let caption: Font = .caption
    static let captionBold: Font = .caption.weight(.semibold)

    // Specialized Display Tokens
    static let metric: Font = .system(.title, design: .rounded, weight: .bold)
    static let badge: Font = .caption.weight(.semibold)
    static let button: Font = .headline.weight(.semibold)
}
