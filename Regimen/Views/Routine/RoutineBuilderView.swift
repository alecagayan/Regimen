//
//  RoutineBuilderView.swift
//  Regimen
//

import SwiftUI

/// Full AM/PM routine assembled from a scan's findings by
/// `RoutineBuilderEngine` -- one step per layering category, each already
/// owned or a catalog suggestion. Reached from a scan's results, premium.
struct RoutineBuilderView: View {
    let counts: [FindingKind: Int]
    let profile: SkinProfile

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var items: [RoutineBuilderEngine.RoutineItem] = []
    @State private var isLoading = true
    @State private var addingCatalogItem: CatalogProduct?
    @State private var addingRoutineTime: RoutineTime?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "Nothing to Build",
                        message: "The catalog doesn't have a product for any step yet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(items) { item in
                                RoutineBuilderRow(item: item) {
                                    addingCatalogItem = item.catalogProduct
                                    addingRoutineTime = item.routineTime
                                }
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Your Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                items = await RoutineBuilderEngine.buildRoutine(for: counts, ownedProducts: appData.products, profile: profile)
                isLoading = false
            }
            .sheet(item: $addingCatalogItem) { catalogItem in
                ProductEditView(product: nil, prefillCatalogItem: catalogItem, prefillRoutineTime: addingRoutineTime)
            }
        }
    }
}

private struct RoutineBuilderRow: View {
    let item: RoutineBuilderEngine.RoutineItem
    let onAdd: () -> Void

    private var isOwned: Bool { item.ownedProduct != nil }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: item.layerCategory.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.layerCategory.rawValue)
                        .font(.sectionLabel)
                        .foregroundStyle(.secondary)
                    StatusChip(text: item.routineTime.rawValue, tint: .secondary)
                }
                Text(item.name)
                    .font(.rowTitle)
                Text(isOwned ? item.reason : "\(item.brand) — \(item.reason)")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if isOwned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.green)
            } else {
                Button("Add", action: onAdd)
                    .font(.rowSubtitle.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
