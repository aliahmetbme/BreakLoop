//
//  BLSettingsRow.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLSettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color = BLColor.brandPrimary
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color = BLColor.brandPrimary,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: BLSpacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 24, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BLTypography.bodyMedium)
                    .foregroundStyle(BLColor.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }
            }

            Spacer()

            accessory()
        }
        .frame(minHeight: 44) // Meets min 44pt touch target guideline
    }
}

extension BLSettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil, iconColor: Color = BLColor.brandPrimary) {
        self.init(title: title, subtitle: subtitle, icon: icon, iconColor: iconColor, accessory: { EmptyView() })
    }
}

#Preview {
    List {
        BLSettingsRow(title: "Usage Limit", subtitle: "Shared across selected apps", icon: "timer") {
            Text("20 min")
                .foregroundStyle(BLColor.brandPrimary)
        }
    }
}
