//
//  ReactionLogView.swift
//  Regimen
//

import SwiftUI

/// Records that skin reacted on a given day.
///
/// The app already knew what was in the cabinet and when each product was
/// started, and the trend chart already drew a line at each of those dates.
/// The missing half was the user's own account of when things went wrong,
/// without which nothing could connect the two.
struct ReactionLogView: View {
    var day: Date = .now

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var severity: ReactionSeverity = .mild
    @State private var note = ""

    private var existing: SkinReaction? { appData.reaction(on: day) }

    /// Products started in the fortnight before this day. A reaction is
    /// usually about something recently introduced, and surfacing the
    /// candidates beats asking the user to remember.
    private var recentlyStarted: [Product] {
        let calendar = Calendar.current
        guard let window = calendar.date(byAdding: .day, value: -14, to: day) else { return [] }
        return appData.products
            .filter { !$0.isArchived }
            .filter { $0.openedDate >= window && $0.openedDate <= day }
            .sorted { $0.openedDate > $1.openedDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("How bad is it?")
                            .font(.cardTitle)
                        ForEach(ReactionSeverity.allCases) { option in
                            Button {
                                severity = option
                            } label: {
                                HStack(spacing: Theme.Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.label)
                                            .font(.rowTitle)
                                            .foregroundStyle(.primary)
                                        Text(option.detail)
                                            .font(.rowSubtitle)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if severity == option {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.brand)
                                    }
                                }
                                .padding(Theme.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .fill(severity == option ? Color.brand.opacity(0.10) : Color.cardSurface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .strokeBorder(severity == option ? Color.brand.opacity(0.5) : Color.subtleBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !recentlyStarted.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Started recently")
                                .font(.cardTitle)
                            Text("Worth considering as a cause.")
                                .font(.rowSubtitle)
                                .foregroundStyle(.secondary)
                            ForEach(recentlyStarted) { product in
                                HStack(spacing: Theme.Spacing.sm) {
                                    ProductAvatar(name: product.name, size: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(product.name)
                                            .font(.rowSubtitle.weight(.medium))
                                        Text(product.openedDate.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.md)
                        .cardStyle()
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Notes")
                            .font(.cardTitle)
                        TextField("What happened?", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.bodyText)
                            .padding(Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(Color.cardSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .strokeBorder(Color.subtleBorder, lineWidth: 1)
                            )
                    }

                    Button {
                        Task {
                            await appData.setReaction(
                                severity: severity,
                                note: note.isEmpty ? nil : note,
                                on: day
                            )
                            dismiss()
                        }
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.primary)

                    if existing != nil {
                        Button("Remove This Entry", role: .destructive) {
                            Task {
                                await appData.clearReaction(on: day)
                                dismiss()
                            }
                        }
                        .font(.rowSubtitle.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Skin Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let existing {
                    severity = existing.severity
                    note = existing.note ?? ""
                }
            }
        }
    }
}
