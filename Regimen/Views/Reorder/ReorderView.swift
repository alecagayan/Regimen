//
//  ReorderView.swift
//  Regimen
//

import SwiftUI

private struct ReorderEntry: Identifiable {
    let product: Product
    let result: DepletionPredictor.Result
    var id: UUID { product.id }
}

struct ReorderView: View {
    @Environment(AppData.self) private var appData
    @Environment(AppNavigation.self) private var navigation

    private var rows: [ReorderEntry] {
        appData.products
            .filter { !$0.isArchived }
            .map { ReorderEntry(product: $0, result: DepletionPredictor.predict(for: $0, usageLogs: appData.usageLogs(for: $0))) }
            .sorted { lhs, rhs in
                // Products without enough usage history to predict a date
                // sort last, regardless of which side of the comparison
                // they're on.
                switch (lhs.result.daysRemaining, rhs.result.daysRemaining) {
                case let (l?, r?): return l < r
                case (nil, nil): return false
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    private var urgentCount: Int {
        rows.filter { ($0.result.daysRemaining ?? .max) <= 14 }.count
    }

    private var subtitle: String {
        urgentCount == 0 ? "Your cabinet's fully stocked" : "\(urgentCount) need\(urgentCount == 1 ? "s" : "") attention soon"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                ScreenHeader(title: "Reorder", subtitle: rows.isEmpty ? nil : subtitle)

                if rows.isEmpty {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "Nothing to Track",
                        message: "Once you add a product and start checking it off, Regimen predicts when it'll run out.",
                        actionTitle: "Add a Product",
                        action: { navigation.startAddingProduct() }
                    )
                    .padding(.top, Theme.Spacing.xl)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(rows) { row in
                                ReorderRow(product: row.product, result: row.result)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ReorderRow: View {
    let product: Product
    let result: DepletionPredictor.Result

    private var urgencyColor: Color {
        // No prediction yet means a full, untouched bottle -- which is the
        // *least* urgent state there is. Tinting it `.secondary` painted a
        // solid dark bar across the row, making the least informative rows
        // the visually heaviest thing on screen; a muted brand tint keeps
        // "nothing to worry about here" reading as calm.
        guard let days = result.daysRemaining else { return .brand.opacity(0.35) }
        if days <= 7 { return .red }
        if days <= 14 { return .orange }
        return .brand
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: product.name, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(product.brand)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressGauge(fraction: result.remainingFraction, tint: urgencyColor)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                if let days = result.daysRemaining {
                    Text(days <= 0 ? "Empty" : "\(days)d")
                        .font(.metricLarge)
                        .foregroundStyle(urgencyColor)
                    if let date = result.predictedEmptyDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No data")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
