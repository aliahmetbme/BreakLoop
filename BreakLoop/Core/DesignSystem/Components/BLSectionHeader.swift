//
//  BLSectionHeader.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 27.10.2026.
//

import SwiftUI

struct BLSectionHeader<ActionContent: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: () -> ActionContent

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder action: @escaping () -> ActionContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: BLSpacing.xxs) {
                Text(title)
                    .font(BLTypography.headline)
                    .foregroundStyle(BLColor.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(BLTypography.caption)
                        .foregroundStyle(BLColor.textSecondary)
                }
            }

            Spacer()

            action()
        }
    }
}

extension BLSectionHeader where ActionContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, action: { EmptyView() })
    }
}

#Preview {
    VStack(spacing: 16) {
        BLSectionHeader(title: "Your BreakLoop", subtitle: "Accumulates across selected apps") {
            Button("Edit") {}
        }
        BLSectionHeader(title: "Session History")
    }
    .padding()
    .background(BLColor.background)
}
