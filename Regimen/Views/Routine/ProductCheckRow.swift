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
            // Checking a product off is the app's core repeated gesture and
            // its only physical-feeling one -- the tap should register in
            // the hand, not just on screen. Unchecking is a correction, so
            // it stays silent.
            if !isChecked {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            Task { await appData.toggleUsageLog(for: product, timeOfDay: timeOfDay) }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                stepBadge

                ProductAvatar(name: product.name, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(product.brand) · \(product.layerCategory.rawValue)")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Below the name/brand, not beside them — a chip
                    // sharing the horizontal HStack with the name squeezes
                    // long product names into an ellipsis almost
                    // immediately (The Ordinary's names run long).
                    if hasConflict {
                        HStack(spacing: 4) {
                            ForEach(product.conflictTags) { tag in
                                StatusChip(text: tag.rawValue, tint: .orange)
                            }
                        }
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
        // Without this the row reads out as its four separate pieces
        // ("3", "Salicylic Acid...", "The Ordinary · Treatment", "checked")
        // with no indication it's one tappable control. Collapsing it into
        // a single toggle is how VoiceOver users actually check a step off.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepNumber). \(product.name), \(product.brand), \(product.layerCategory.rawValue)")
        .accessibilityValue(isChecked ? "Used" : "Not used")
        .accessibilityHint(isChecked ? "Double tap to mark as not used" : "Double tap to mark as used")
        .accessibilityAddTraits(.isButton)
    }

    private var stepBadge: some View {
        // Fixed size: the numeral is pinned inside a 22pt circle and would
        // overflow it if it grew with Dynamic Type.
        Text("\(stepNumber)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.brand)
            .frame(width: 22, height: 22)
            .background(Color.brand.opacity(0.12), in: Circle())
    }
}
