//
//  RoutineBuilderView.swift
//  Regimen
//

import SwiftUI

/// Full AM/PM routine assembled from a scan's findings by
/// `RoutineBuilderEngine` -- one step per layering category, each already
/// owned or a catalog suggestion. Reached from a scan's results, premium.
///
/// Split into morning and evening sections rather than shown as one flat
/// list: a routine *is* two sequences, and a single list with a small
/// "AM"/"PM" chip per row left the reader to mentally sort it themselves.
/// Steps marked `.both` appear in each section, which is what actually
/// happens on the face.
struct RoutineBuilderView: View {
    let counts: [FindingKind: Int]
    let profile: SkinProfile

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var items: [RoutineBuilderEngine.RoutineItem] = []
    @State private var isLoading = true
    @State private var addingCatalogItem: CatalogProduct?
    @State private var addingRoutineTime: RoutineTime?
    @State private var addingFrequency: ProductFrequency?

    private var morning: [RoutineBuilderEngine.RoutineItem] { items.filter(\.isMorning) }
    private var evening: [RoutineBuilderEngine.RoutineItem] { items.filter(\.isEvening) }

    /// How many steps the user would still need to buy -- the honest
    /// headline for someone deciding whether this routine is realistic.
    private var missingCount: Int { items.filter { !$0.isOwned }.count }

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
                        message: "The catalog has nothing for these steps yet."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.lg) {
                            summaryCard

                            routineSection(
                                title: "Morning",
                                icon: "sun.max.fill",
                                items: morning
                            )

                            routineSection(
                                title: "Evening",
                                icon: "moon.fill",
                                items: evening
                            )

                            Text("Based on this scan and what you told us. Not medical advice.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
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
                items = await RoutineBuilderEngine.buildRoutine(
                    for: counts,
                    ownedProducts: appData.products,
                    profile: profile,
                    empties: appData.empties
                )
                isLoading = false
            }
            .sheet(item: $addingCatalogItem) { catalogItem in
                ProductEditView(
                    product: nil,
                    prefillCatalogItem: catalogItem,
                    prefillRoutineTime: addingRoutineTime,
                    prefillFrequency: addingFrequency
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(items.count) step\(items.count == 1 ? "" : "s")")
                .font(.cardTitle)
            Text(
                missingCount == 0
                    ? "You already own everything in this routine."
                    : "\(items.count - missingCount) already in your cabinet, \(missingCount) to add."
            )
            .font(.rowSubtitle)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    @ViewBuilder
    private func routineSection(
        title: String,
        icon: String,
        items sectionItems: [RoutineBuilderEngine.RoutineItem]
    ) -> some View {
        if !sectionItems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label(title, systemImage: icon)
                    .font(.cardTitle)
                    .foregroundStyle(Color.brand)

                ForEach(Array(sectionItems.enumerated()), id: \.element.id) { index, item in
                    RoutineBuilderRow(item: item, stepNumber: index + 1) {
                        addingCatalogItem = item.catalogProduct
                        addingRoutineTime = item.routineTime
                        addingFrequency = item.frequency
                    }
                }
            }
        }
    }
}

private struct RoutineBuilderRow: View {
    let item: RoutineBuilderEngine.RoutineItem
    /// Position within its own AM/PM section -- the layering order is the
    /// whole point of the list, so it's numbered rather than left implicit.
    let stepNumber: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.brand.gradient)
                    .frame(width: 36, height: 36)
                Text("\(stepNumber)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label(item.layerCategory.rawValue, systemImage: item.layerCategory.icon)
                        .font(.sectionLabel)
                        .foregroundStyle(.secondary)
                    if item.routineTime == .both {
                        StatusChip(text: "AM + PM", tint: .secondary)
                    }
                    if !item.frequency.isDaily {
                        StatusChip(text: item.frequency.shortLabel, tint: .brand)
                    }
                }
                Text(item.name)
                    .font(.rowTitle)
                Text(item.isOwned ? item.reason : "\(item.brand). \(item.reason)")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if item.isOwned {
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
