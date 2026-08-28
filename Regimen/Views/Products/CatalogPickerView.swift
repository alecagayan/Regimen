//
//  CatalogPickerView.swift
//  Regimen
//

import SwiftUI

/// Search sheet over `catalog_products`. Selecting a result hands it back
/// to the caller (see `ProductEditView`) to pre-fill the Add Product form
/// — it doesn't create anything itself.
struct CatalogPickerView: View {
    var onSelect: (CatalogProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CatalogProduct] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && results.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Matches",
                        message: "Try a different product name."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(results) { item in
                                Button {
                                    onSelect(item)
                                    dismiss()
                                } label: {
                                    CatalogRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Product Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await CatalogService.search(query)) ?? []
    }
}

private struct CatalogRow: View {
    let item: CatalogProduct

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: item.name, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.emphasized(15))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Label(item.layerCategory.rawValue, systemImage: item.layerCategory.icon)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                if item.suggestedConflictTag != .none {
                    StatusChip(text: item.suggestedConflictTag.rawValue, tint: .orange)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
