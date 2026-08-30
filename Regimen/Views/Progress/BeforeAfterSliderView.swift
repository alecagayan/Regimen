//
//  BeforeAfterSliderView.swift
//  Regimen
//

import SwiftUI

/// A drag-to-reveal before/after comparison. This is intentionally just a
/// masked overlay driven by a drag gesture — no image alignment/registration
/// and no computer-vision diffing. For v1, the user's own eye comparing two
/// photos side by side is the whole "algorithm"; this view's only job is to
/// let them control how much of each photo is visible.
///
/// Takes signed Supabase Storage URLs rather than `ProgressPhoto` values, so
/// this view has no dependency on where the images actually live.
struct BeforeAfterSliderView: View {
    let beforeURL: URL?
    let afterURL: URL?

    @State private var sliderPosition: CGFloat = 0.5
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    imageView(afterURL)

                    imageView(beforeURL)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geometry.size.width * sliderPosition)
                        }

                    Rectangle()
                        .fill(.white)
                        .frame(width: 2)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .offset(x: geometry.size.width * sliderPosition - 1)

                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                        .position(x: geometry.size.width * sliderPosition, y: geometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = value.location.x / geometry.size.width
                            sliderPosition = min(max(fraction, 0), 1)
                        }
                )
                .overlay(alignment: .top) {
                    HStack {
                        compareLabel("BEFORE")
                        Spacer()
                        compareLabel("AFTER")
                    }
                    .padding()
                    .background(
                        LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                            .ignoresSafeArea(edges: .top),
                        alignment: .top
                    )
                }
            }
            .background(.black)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
            }
        }
    }

    private func compareLabel(_ text: String) -> some View {
        Text(text)
            .font(.chipLabel)
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.35), in: Capsule())
    }

    @ViewBuilder
    private func imageView(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle().fill(.gray.opacity(0.3))
            }
        }
    }
}
