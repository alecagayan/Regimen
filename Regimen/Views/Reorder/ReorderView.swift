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

    @State private var repurchasing: Product?
    @State private var showingShoppingList = false

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
                ScreenHeader(title: "Reorder", subtitle: rows.isEmpty ? nil : subtitle) {
                    if urgentCount > 0 {
                        Button {
                            showingShoppingList = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.brand)
                        }
                        .accessibilityLabel("Share shopping list")
                    }
                }

                if rows.isEmpty {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "Nothing to Track",
                        message: "Add a product and start checking it off, and Regimen predicts when it runs out.",
                        actionTitle: "Add a Product",
                        action: { navigation.startAddingProduct() }
                    )
                    .padding(.top, Theme.Spacing.xl)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(rows) { row in
                                ReorderRow(
                                    product: row.product,
                                    result: row.result,
                                    onRepurchased: { repurchasing = row.product }
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .refreshable { await appData.loadAll() }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingShoppingList) {
                ShareSheet(items: [shoppingListText])
            }
            .confirmationDialog(
                repurchasing.map { "Started a new \($0.name)?" } ?? "Started a new bottle?",
                isPresented: Binding(
                    get: { repurchasing != nil },
                    set: { if !$0 { repurchasing = nil } }
                ),
                titleVisibility: .visible,
                presenting: repurchasing
            ) { product in
                Button("Yes, It's a Fresh Bottle") {
                    Task { await markRepurchased(product) }
                    repurchasing = nil
                }
                Button("Cancel", role: .cancel) { repurchasing = nil }
            } message: { _ in
                Text("Resets the bottle to full from today. Your check-off history and streak are kept.")
            }
        }
    }

    /// Everything running low, as plain text to paste into notes or send
    /// to whoever does the shopping.
    private var shoppingListText: String {
        let low = rows.filter { ($0.result.daysRemaining ?? .max) <= 14 }
        let lines = low.map { row -> String in
            let days = row.result.daysRemaining ?? 0
            let when = days <= 0 ? "empty" : "~\(days) days left"
            return "• \(row.product.name) (\(row.product.brand)): \(when)"
        }
        return (["Running low:"] + lines).joined(separator: "\n")
    }

    /// A repurchase is just a new opened date -- `DepletionPredictor` only
    /// counts usage from that point, so the bottle refills without throwing
    /// away a single log.
    private func markRepurchased(_ product: Product) async {
        var updated = product
        updated.openedDate = .now
        await appData.updateProduct(updated)
    }
}

private struct ReorderRow: View {
    let product: Product
    let result: DepletionPredictor.Result
    let onRepurchased: () -> Void

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

            VStack(alignment: .trailing, spacing: 4) {
                if let days = result.daysRemaining {
                    Text(days <= 0 ? "Empty" : "\(days)d")
                        .font(.metricLarge)
                        .foregroundStyle(urgencyColor)
                    if let date = result.predictedEmptyDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // The whole point of the tab, and it had no control at
                    // all: when something ran out the only route back was
                    // Cabinet > Edit > change the opened date by hand.
                    if days <= 14 {
                        Button("Restocked", action: onRepurchased)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brand)
                            .controlSize(.small)
                    }
                } else {
                    Text("No data yet")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                    // "No data" alone gave no sense of whether this was
                    // broken or just early.
                    Text("Check it off a few times")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(minWidth: 78, alignment: .trailing)
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .contextMenu {
            Button("Mark as Restocked", systemImage: "arrow.clockwise", action: onRepurchased)
        }
    }
}
