//
//  CategoryProductsView.swift
//  Regimen
//

import SwiftUI

/// Every catalog product that targets one ingredient category — reached by
/// tapping a category card in PhotoDetailView's "What to Use" section.
/// Browse-only (no onSelect): unlike CatalogPickerView this isn't part of
/// the add-product flow, just "show me what's out there for this."
struct CategoryProductsView: View {
    let tag: ConflictTag

    @Environment(\.dismiss) private var dismiss
    @State private var products: [CatalogProduct] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if products.isEmpty {
                    EmptyStateView(
                        icon: tag.icon,
                        title: "Nothing Yet",
                        message: "No catalog products target \(tag.rawValue) yet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(products) { item in
                                CategoryProductRow(item: item)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(tag.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                products = (try? await CatalogService.products(withConflictTag: tag)) ?? []
                isLoading = false
            }
        }
    }
}

private struct CategoryProductRow: View {
    let item: CatalogProduct

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: item.name, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.rowTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(item.brand)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                Label(item.layerCategory.rawValue, systemImage: item.layerCategory.icon)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                if let productDescription = item.productDescription {
                    Text(productDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
