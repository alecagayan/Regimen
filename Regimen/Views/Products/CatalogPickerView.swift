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
    /// Brands the user has manually toggled open, and manually toggled
    /// shut -- two sets, not a single "expanded" set, because a brand's
    /// *default* state depends on whether there's an active search (see
    /// `isExpanded`), and a plain toggle needs to override that default in
    /// either direction. Six-plus brands and 100+ products meant the list
    /// used to open as one long undifferentiated scroll — collapsed brand
    /// sections make "which brands are even in here" scannable at a
    /// glance instead.
    @State private var expandedBrands: Set<String> = []
    @State private var collapsedBrands: Set<String> = []

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
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(brandSections, id: \.brand) { section in
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    brandHeader(section)

                                    if isExpanded(section.brand) {
                                        ForEach(section.items) { item in
                                            Button {
                                                onSelect(item)
                                                dismiss()
                                            } label: {
                                                CatalogRow(item: item)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
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

    private func brandHeader(_ section: (brand: String, items: [CatalogProduct])) -> some View {
        Button {
            toggle(section.brand)
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(section.brand)
                    .font(.sectionLabel)
                    .foregroundStyle(.primary)
                Text("\(section.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded(section.brand) ? 90 : 0))
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A brand reads as expanded once the user has opened it, or -- while
    /// actively searching -- by default: `CatalogService.search` already
    /// narrows the list to a few relevant rows, so making the user tap
    /// through a collapsed section just to see a one-result match would be
    /// friction the search bar was supposed to remove. Manually collapsing
    /// a brand during a search still works, via the same toggle.
    private func isExpanded(_ brand: String) -> Bool {
        if expandedBrands.contains(brand) { return true }
        if collapsedBrands.contains(brand) { return false }
        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggle(_ brand: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isExpanded(brand) {
                expandedBrands.remove(brand)
                collapsedBrands.insert(brand)
            } else {
                collapsedBrands.remove(brand)
                expandedBrands.insert(brand)
            }
        }
    }

    /// Groups `results` into brand sections, preserving the order they
    /// came back in (CatalogService already sorts by brand, then name) so
    /// this doesn't need to re-sort.
    private var brandSections: [(brand: String, items: [CatalogProduct])] {
        var order: [String] = []
        var grouped: [String: [CatalogProduct]] = [:]
        for item in results {
            if grouped[item.brand] == nil { order.append(item.brand) }
            grouped[item.brand, default: []].append(item)
        }
        return order.map { (brand: $0, items: grouped[$0] ?? []) }
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
                    .font(.rowTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Label(item.layerCategory.rawValue, systemImage: item.layerCategory.icon)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                if let productDescription = item.productDescription {
                    Text(productDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !item.suggestedConflictTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.suggestedConflictTags) { tag in
                            StatusChip(text: tag.rawValue, tint: .orange)
                        }
                    }
                }
            }

            Spacer(minLength: Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
