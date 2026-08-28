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
        urgentCount == 0 ? "Everything's well stocked" : "\(urgentCount) need\(urgentCount == 1 ? "s" : "") attention soon"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ScreenHeader(title: "Reorder", subtitle: rows.isEmpty ? nil : subtitle)

                    if rows.isEmpty {
                        EmptyStateView(
                            icon: "shippingbox",
                            title: "No Products",
                            message: "Add products in the Products tab to start tracking depletion."
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(rows) { row in
                                ReorderRow(product: row.product, result: row.result)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
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
        guard let days = result.daysRemaining else { return .secondary }
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
                        .font(.emphasized(16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(product.brand)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressGauge(fraction: result.remainingFraction, tint: urgencyColor)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                if let days = result.daysRemaining {
                    Text(days <= 0 ? "Empty" : "\(days)d")
                        .font(.display(20))
                        .foregroundStyle(urgencyColor)
                    if let date = result.predictedEmptyDate {
                        Text(date, style: .date)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No data")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
