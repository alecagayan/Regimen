//
//  RoutineView.swift
//  Regimen
//

import SwiftUI

struct RoutineView: View {
    @Environment(AppData.self) private var appData

    @State private var selectedTime: TimeOfDay = .am

    private var activeProducts: [Product] {
        let filtered = appData.products
            .filter { !$0.isArchived }
            .filter { $0.routineTime == .both || $0.routineTime.rawValue == selectedTime.rawValue }
        return LayeringAdvisor.recommendedOrder(for: filtered)
    }

    private var conflicts: [ConflictChecker.Conflict] {
        ConflictChecker.conflicts(among: activeProducts)
    }

    /// Only products actually named in a detected conflict get a tag on
    /// their row — having a conflict-prone ingredient isn't itself worth
    /// flagging if nothing it's paired with today actually interacts badly.
    private var conflictedProductIDs: Set<UUID> {
        conflicts.reduce(into: Set<UUID>()) { ids, conflict in
            ids.insert(conflict.productA.id)
            ids.insert(conflict.productB.id)
        }
    }

    private var todaySubtitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ScreenHeader(title: "Routine", subtitle: todaySubtitle)

                    PillToggle(selection: $selectedTime, title: \.rawValue)
                        .padding(.horizontal, Theme.Spacing.lg)

                    if !conflicts.isEmpty {
                        ConflictBanner(conflicts: conflicts)
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    if activeProducts.isEmpty {
                        EmptyStateView(
                            icon: "checklist",
                            title: "No Products for \(selectedTime.rawValue)",
                            message: "Add a product and set its routine time in the Products tab."
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Shown in recommended application order")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.lg)

                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(activeProducts.enumerated()), id: \.element.id) { index, product in
                                ProductCheckRow(
                                    product: product,
                                    timeOfDay: selectedTime,
                                    stepNumber: index + 1,
                                    hasConflict: conflictedProductIDs.contains(product.id)
                                )
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
