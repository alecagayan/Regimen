//
//  FinishedProductView.swift
//  Regimen
//

import SwiftUI

/// Captures how a product went, at the one moment the user actually knows:
/// when the bottle is empty.
///
/// Archives rather than deletes. The usage history behind a finished
/// product is what every prediction and the whole streak are built from, so
/// throwing it away to tidy the cabinet would be the most expensive kind of
/// cleanup.
struct FinishedProductView: View {
    let product: Product

    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    @State private var wouldRepurchase: Bool?
    @State private var rating = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.cardTitle)
                        Text("Used \(appData.usageLogs(for: product).count) times since \(product.openedDate.formatted(.dateTime.month(.abbreviated).year()))")
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }

                    section("Would you buy it again?") {
                        HStack(spacing: Theme.Spacing.sm) {
                            choice(title: "Yes", isSelected: wouldRepurchase == true) { wouldRepurchase = true }
                            choice(title: "No", isSelected: wouldRepurchase == false) { wouldRepurchase = false }
                        }
                    }

                    section("How was it?") {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    // Tapping the current rating clears it,
                                    // so a mis-tap isn't permanent.
                                    rating = rating == value ? 0 : value
                                } label: {
                                    Image(systemName: value <= rating ? "star.fill" : "star")
                                        .font(.title3)
                                        .foregroundStyle(value <= rating ? Color.brand : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    section("Anything worth remembering?") {
                        TextField("Optional", text: $note, axis: .vertical)
                            .lineLimit(2...4)
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
                            await appData.recordEmpty(
                                for: product,
                                wouldRepurchase: wouldRepurchase,
                                rating: rating > 0 ? rating : nil,
                                note: note.isEmpty ? nil : note
                            )
                            dismiss()
                        }
                    } label: {
                        Label("Log Empty & Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.primary)

                    Text("Archiving hides it from your routine. Your check-off history stays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.rowTitle)
            content()
        }
    }

    private func choice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.controlLabel)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(isSelected ? Color.brand.gradient : Color.cardSurface.gradient)
                )
                .overlay(Capsule().strokeBorder(Color.subtleBorder, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// The shelf of everything finished, reachable from the Cabinet.
struct EmptiesView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appData.empties.isEmpty {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "No Empties Yet",
                        message: "When you finish a product, log it here to keep a record of what worked."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(appData.empties) { empty in
                                EmptyRow(empty: empty)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Empties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct EmptyRow: View {
    let empty: ProductEmpty

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: empty.productName, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(empty.productName)
                    .font(.rowTitle)
                Text("\(empty.brand) · finished \(empty.finishedOn.formatted(.dateTime.month(.abbreviated).year()))")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                if let rating = empty.rating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { value in
                            Image(systemName: value <= rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(Color.brand)
                        }
                    }
                    .accessibilityLabel("\(rating) out of 5")
                }
                if let note = empty.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            if let wouldRepurchase = empty.wouldRepurchase {
                StatusChip(
                    text: wouldRepurchase ? "Would rebuy" : "Wouldn't rebuy",
                    tint: wouldRepurchase ? .brand : .secondary
                )
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}
