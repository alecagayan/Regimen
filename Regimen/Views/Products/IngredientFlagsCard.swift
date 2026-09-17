//
//  IngredientFlagsCard.swift
//  Regimen
//

import SwiftUI

/// What `IngredientInsights` found in a product's INCI list.
///
/// Phrased as observations, never verdicts: "contains fragrance" is a fact
/// about a label, while "this will irritate you" would be a claim about a
/// person the app has no way to make. The one exception is the pregnancy
/// caution, which is coloured differently because it's the only flag where
/// the right response is to ask someone qualified.
struct IngredientFlagsCard: View {
    let ingredients: [String]
    /// Shown collapsed by default -- an INCI list is 30+ entries of Latin
    /// and reads as noise until someone specifically wants it.
    @State private var showingFullList = false

    private var flags: [IngredientInsights.Flag] {
        IngredientInsights.flags(for: ingredients)
    }

    var body: some View {
        if !ingredients.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("INGREDIENTS")
                    .font(.sectionLabel)
                    .foregroundStyle(.secondary)

                if flags.isEmpty {
                    Label("Nothing notable flagged.", systemImage: "checkmark.circle")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(flags) { flag in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: flag.kind.icon)
                                .font(.footnote)
                                .foregroundStyle(flag.kind.isCaution ? .orange : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(flag.kind.label)
                                    .font(.rowSubtitle.weight(.semibold))
                                    .foregroundStyle(flag.kind.isCaution ? .orange : .primary)
                                Text(flag.kind.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(flag.matches.joined(separator: ", ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Button(showingFullList ? "Hide full list" : "Show all \(ingredients.count) ingredients") {
                    withAnimation { showingFullList.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brand)

                if showingFullList {
                    Text(ingredients.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .cardStyle()
        }
    }
}
