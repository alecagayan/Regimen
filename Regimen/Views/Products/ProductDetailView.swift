//
//  ProductDetailView.swift
//  Regimen
//

import SwiftUI

/// What the app actually knows about one product: how much is left, how
/// often it gets used, what's in it, and where it sits in the routine.
///
/// Tapping a Cabinet row used to open the *edit form* -- so every piece of
/// this, all of it already tracked, was only ever visible in aggregate on
/// other screens. Editing is still here, one tap away, but it's no longer
/// the only thing a product can do.
struct ProductDetailView: View {
    let product: Product

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showingRepurchaseConfirmation = false
    @State private var showingFinishedSheet = false

    /// Re-read from AppData so an edit made in the sheet is reflected here
    /// the moment it closes.
    private var current: Product {
        appData.products.first { $0.id == product.id } ?? product
    }

    private var logs: [UsageLog] {
        appData.usageLogs(for: current)
    }

    private var prediction: DepletionPredictor.Result {
        DepletionPredictor.predict(for: current, usageLogs: logs)
    }

    private var usesThisBottle: Int {
        let start = Calendar.current.startOfDay(for: current.openedDate)
        return logs.filter { $0.timestamp >= start }.count
    }

    private var lastUsed: Date? {
        logs.map(\.timestamp).max()
    }

    /// Conflicts this product is actually involved in, against the rest of
    /// the active cabinet -- the same check the Routine tab runs.
    private var conflicts: [ConflictChecker.Conflict] {
        let active = appData.products.filter { !$0.isArchived }
        return ConflictChecker.conflicts(among: active)
            .filter { $0.productA.id == current.id || $0.productB.id == current.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    header
                    bottleCard
                    usageCard
                    if !current.conflictTags.isEmpty { ingredientsCard }
                    IngredientFlagsCard(ingredients: current.ingredients)
                    if !conflicts.isEmpty { conflictsCard }
                    finishedCard
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProductEditView(product: current)
            }
            .sheet(isPresented: $showingFinishedSheet) {
                FinishedProductView(product: current)
            }
            .confirmationDialog(
                "Started a new \(current.name)?",
                isPresented: $showingRepurchaseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, It's a Fresh Bottle") {
                    Task {
                        var updated = current
                        updated.openedDate = .now
                        await appData.updateProduct(updated)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Resets the bottle to full from today. Your check-off history and streak are kept.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: current.name, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(current.brand)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    StatusChip(text: current.routineTime.rawValue, tint: .secondary)
                    StatusChip(text: current.layerCategory.rawValue, tint: .secondary)
                    if !current.frequency.isDaily {
                        StatusChip(text: current.frequency.shortLabel, tint: .brand)
                    }
                    if current.isArchived {
                        StatusChip(text: "Archived", tint: .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private var bottleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("BOTTLE")
                    .font(.sectionLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                if let days = prediction.daysRemaining {
                    Text(days <= 0 ? "Empty" : "~\(days) days left")
                        .font(.rowSubtitle.weight(.semibold))
                        .foregroundStyle(days <= 7 ? .red : (days <= 14 ? .orange : Color.brand))
                }
            }

            ProgressGauge(fraction: prediction.remainingFraction, tint: Color.brand)

            Text("\(Int(prediction.remainingFraction * 100))% of \(Int(current.sizeInML)) mL left · opened \(current.openedDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let rate = prediction.averageMLPerDay, rate > 0 {
                Text("Using about \(rate, format: .number.precision(.fractionLength(2))) mL a day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Shelf life, once the user has recorded the jar symbol.
            if let shelfLifeNote = current.shelfLifeNote {
                Label(shelfLifeNote, systemImage: current.isExpired ? "exclamationmark.triangle.fill" : "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(current.isExpired ? .red : .orange)
            }

            Divider().padding(.vertical, 2)

            Button {
                showingRepurchaseConfirmation = true
            } label: {
                Label("Mark as Restocked", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// Finishing a bottle is the one moment the app can learn whether a
    /// product was worth using, and it had nowhere to record that.
    private var finishedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("FINISHED IT?")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)
            Text("Log it as an empty to keep the history and archive the product.")
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
            Button {
                showingFinishedSheet = true
            } label: {
                Label("Log as Empty", systemImage: "checkmark.circle")
            }
            .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("USAGE")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.lg) {
                stat(value: "\(logs.count)", label: "Total uses")
                stat(value: "\(usesThisBottle)", label: "This bottle")
                stat(
                    value: lastUsed.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Never",
                    label: "Last used"
                )
            }

            if logs.isEmpty {
                Text("Check this off in the Routine tab and its usage will start showing here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.metric)
                .foregroundStyle(Color.brand)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ACTIVE INGREDIENTS")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(current.conflictTags) { tag in
                    StatusChip(text: tag.rawValue, tint: .brand)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private var conflictsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Conflicts", systemImage: "exclamationmark.triangle.fill")
                .font(.cardTitle)
                .foregroundStyle(.orange)

            ForEach(conflicts) { conflict in
                let other = conflict.productA.id == current.id ? conflict.productB : conflict.productA
                VStack(alignment: .leading, spacing: 2) {
                    Text("With \(other.name)")
                        .font(.rowTitle)
                    Text(conflict.reason)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
