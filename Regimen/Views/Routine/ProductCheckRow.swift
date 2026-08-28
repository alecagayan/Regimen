//
//  ProductCheckRow.swift
//  Regimen
//

import SwiftUI

/// One checklist card in `RoutineView`. Tapping toggles today's usage log
/// for this product/time-of-day, which is what feeds `DepletionPredictor`.
struct ProductCheckRow: View {
    @Environment(AppData.self) private var appData

    let product: Product
    let timeOfDay: TimeOfDay
    /// This product's position in `LayeringAdvisor.recommendedOrder` for
    /// today's active products — shown as a small step badge so the
    /// recommended application order is visible at a glance, not just
    /// implied by list position.
    let stepNumber: Int
    /// Whether this product is actually named in one of today's detected
    /// conflicts (computed by `RoutineView`) — not just whether it *has* a
    /// conflict-prone ingredient tag. A retinoid sitting alone in tonight's
    /// routine isn't "conflicting" with anything.
    let hasConflict: Bool

    private var isChecked: Bool {
        let calendar = Calendar.current
        return appData.usageLogs(for: product).contains {
            $0.timeOfDay == timeOfDay && calendar.isDateInToday($0.timestamp)
        }
    }

    var body: some View {
        Button {
            Task { await appData.toggleUsageLog(for: product, timeOfDay: timeOfDay) }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                stepBadge

                ProductAvatar(name: product.name, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.emphasized(16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(product.brand) · \(product.layerCategory.rawValue)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Below the name/brand, not beside them — a chip
                    // sharing the horizontal HStack with the name squeezes
                    // long product names into an ellipsis almost
                    // immediately (The Ordinary's names run long).
                    if hasConflict {
                        StatusChip(text: product.conflictTag.rawValue, tint: .orange)
                    }
                }

                Spacer(minLength: Theme.Spacing.sm)

                ZStack {
                    Circle()
                        .fill(isChecked ? Color.brand : Color.clear)
                    Circle()
                        .strokeBorder(isChecked ? Color.clear : Color.subtleBorder, lineWidth: 2)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
            .opacity(isChecked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isChecked)
    }

    private var stepBadge: some View {
        Text("\(stepNumber)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.brand)
            .frame(width: 22, height: 22)
            .background(Color.brand.opacity(0.12), in: Circle())
    }
}
