//
//  ProgressTabView.swift
//  Regimen
//
//  Named `ProgressTabView` (not `ProgressView`) to avoid colliding with
//  SwiftUI's own `ProgressView` type.
//

import SwiftUI
import PhotosUI

struct ProgressTabView: View {
    @Environment(AppData.self) private var appData

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var selectionForCompare: [ProgressPhoto] = []
    @State private var showingComparison = false

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible(), spacing: Theme.Spacing.sm)]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        HStack(alignment: .top) {
                            ScreenHeader(
                                title: "Progress",
                                subtitle: appData.progressPhotos.isEmpty
                                    ? nil
                                    : "\(appData.progressPhotos.count) photo\(appData.progressPhotos.count == 1 ? "" : "s")"
                            )
                            Spacer()
                            addMenu
                                .padding(.top, Theme.Spacing.md)
                                .padding(.trailing, Theme.Spacing.lg)
                        }

                        if appData.progressPhotos.isEmpty {
                            EmptyStateView(
                                icon: "camera",
                                title: "No Photos",
                                message: "Add a progress photo to start a timeline."
                            )
                            .padding(.top, Theme.Spacing.xl)
                        } else {
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                                ForEach(appData.progressPhotos) { photo in
                                    PhotoThumbnail(
                                        photo: photo,
                                        url: appData.signedPhotoURLs[photo.storagePath],
                                        isSelected: selectionForCompare.contains(photo)
                                    )
                                    .onTapGesture { toggleSelection(photo) }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .background(Color.appBackground.ignoresSafeArea())

                if selectionForCompare.count == 2 {
                    Button {
                        showingComparison = true
                    } label: {
                        Label("Compare Selected", systemImage: "rectangle.split.2x1.fill")
                            .font(.emphasized(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brand.gradient, in: Capsule())
                            .shadow(color: Color.brand.opacity(0.35), radius: 14, x: 0, y: 8)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectionForCompare.count)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: photosPickerItem) { _, newItem in
                Task { await importFromPhotoLibrary(newItem) }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        showingCamera = false
                        Task { await appData.addPhoto(image: image) }
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingComparison) {
                if selectionForCompare.count == 2 {
                    let sorted = selectionForCompare.sorted { $0.timestamp < $1.timestamp }
                    BeforeAfterSliderView(
                        beforeURL: appData.signedPhotoURLs[sorted[0].storagePath],
                        afterURL: appData.signedPhotoURLs[sorted[1].storagePath]
                    )
                }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.brand.gradient, in: Circle())
                .shadow(color: Color.brand.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }

    private func toggleSelection(_ photo: ProgressPhoto) {
        if let index = selectionForCompare.firstIndex(of: photo) {
            selectionForCompare.remove(at: index)
        } else {
            // The slider only ever compares a pair, so cap selection at 2 by
            // dropping the oldest selection once a third is tapped.
            if selectionForCompare.count == 2 {
                selectionForCompare.removeFirst()
            }
            selectionForCompare.append(photo)
        }
    }

    private func importFromPhotoLibrary(_ item: PhotosPickerItem?) async {
        guard
            let item,
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else { return }
        await appData.addPhoto(image: image)
        photosPickerItem = nil
    }
}

private struct PhotoThumbnail: View {
    let photo: ProgressPhoto
    let url: URL?
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.subtleBorder)
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fill)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 56)

            HStack {
                Text(photo.timestamp, style: .date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(10)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.brand : Color.clear, lineWidth: 3)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                ZStack {
                    Circle().fill(Color.brand)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .padding(8)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}
