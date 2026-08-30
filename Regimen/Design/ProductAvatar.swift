//
//  ProductAvatar.swift
//  Regimen
//

import SwiftUI

/// A colored initial "chip" for a product, used anywhere a product appears
/// in a list — stands in for product photography without needing any.
struct ProductAvatar: View {
    let name: String
    var size: CGFloat = 44

    private static let palette: [Color] = [
        Color(red: 0.60, green: 0.72, blue: 0.62), // sage
        Color(red: 0.82, green: 0.62, blue: 0.52), // terracotta
        Color(red: 0.58, green: 0.67, blue: 0.79), // dusty blue
        Color(red: 0.78, green: 0.61, blue: 0.70), // mauve
        Color(red: 0.85, green: 0.71, blue: 0.42), // ochre
        Color(red: 0.68, green: 0.56, blue: 0.66), // plum
    ]

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.first!).uppercased()
    }

    private var tint: Color {
        // A hand-rolled FNV-1a hash rather than `String.hashValue`: Swift's
        // built-in hash is seeded randomly per process, so relying on it
        // would give every product a different avatar color each launch.
        var hash: UInt64 = 14695981039346656037
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Self.palette[Int(hash % UInt64(Self.palette.count))]
    }

    var body: some View {
        Circle()
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            // Decorative: it stands in for product photography, and the
            // product's name is always read out right beside it.
            .accessibilityHidden(true)
    }
}
