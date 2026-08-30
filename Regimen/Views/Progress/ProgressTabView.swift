//
//  ProgressTabView.swift
//  Regimen
//
//  Named `ProgressTabView` (not `ProgressView`) to avoid colliding with
//  SwiftUI's own `ProgressView` type.
//

import Charts
import SwiftUI
import PhotosUI

struct ProgressTabView: View {
    @Environment(AppData.self) private var appData

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var selectionForCompare: [ProgressPhoto] = []
    @State private var showingComparison = false
    @State private var detailPhoto: ProgressPhoto?
    @State private var showingPhotoPicker = false
    /// The empty state's call to action opens the same camera/library
    /// choice the floating + menu offers, as a dialog rather than a menu --
    /// a menu anchored to a button in the middle of an empty screen reads
    /// as a dead end.
    @State private var showingPhotoSourceDialog = false

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible(), spacing: Theme.Spacing.sm)]

    /// Scanned photos, oldest first, for the trend chart -- appData.progressPhotos
    /// itself is newest-first (matches the grid, which should show the most
    /// recent photo first) so this reverses just for charting.
    private var scoredPhotos: [ProgressPhoto] {
        appData.progressPhotos
            .filter { $0.skinScore != nil }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    ScreenHeader(
                        title: "Progress",
                        subtitle: appData.progressPhotos.isEmpty
                            ? nil
                            : "\(appData.progressPhotos.count) photo\(appData.progressPhotos.count == 1 ? "" : "s")"
                    )

                    ScrollView {
                        if appData.progressPhotos.isEmpty {
                            EmptyStateView(
                                icon: "camera",
                                title: "Blank Slate",
                                message: "Take a well-lit, front-facing photo. Regimen scans it on-device for problem areas and tracks how your skin changes.",
                                actionTitle: "Add Your First Photo",
                                action: { showingPhotoSourceDialog = true }
                            )
                            .padding(.top, Theme.Spacing.xl)
                        } else {
                            VStack(spacing: Theme.Spacing.sm) {
                                if !appData.usageLogs.isEmpty {
                                    PremiumGate(
                                        isPremium: appData.isPremium,
                                        title: "Weekly Insight Digest",
                                        message: "Days logged, streak, score movement, and what's running low, at a glance."
                                    ) {
                                        WeeklyDigestCard(digest: WeeklyDigestEngine.build(
                                            products: appData.products,
                                            usageLogs: appData.usageLogs,
                                            progressPhotos: appData.progressPhotos
                                        ))
                                    }
                                }

                                if scoredPhotos.count >= 2 {
                                    PremiumGate(
                                        isPremium: appData.isPremium,
                                        title: "Skin Score Trend",
                                        message: "A chart of your score over time, with markers for when you started new products."
                                    ) {
                                        SkinScoreTrendCard(photos: scoredPhotos, products: appData.products)
                                    }

                                    let zoneProgress = PerZoneProgressEngine.build(zoneFindings: appData.zoneFindings, progressPhotos: appData.progressPhotos)
                                    if !zoneProgress.isEmpty {
                                        PremiumGate(
                                            isPremium: appData.isPremium,
                                            title: "Per-Zone Progress",
                                            message: "See which face zones have improved since your first scan."
                                        ) {
                                            PerZoneProgressCard(zoneProgress: zoneProgress)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.md)

                            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                                ForEach(appData.progressPhotos) { photo in
                                    PhotoThumbnail(
                                        photo: photo,
                                        url: appData.signedPhotoURLs[photo.storagePath],
                                        isSelected: selectionForCompare.contains(photo),
                                        onShowDetail: { detailPhoto = photo }
                                    )
                                    .onTapGesture { toggleSelection(photo) }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.floatingButtonClearance)
                        }
                    }
                }
                .background(Color.appBackground.ignoresSafeArea())

                if selectionForCompare.count == 2 {
                    Button {
                        showingComparison = true
                    } label: {
                        Label("Compare Selected", systemImage: "rectangle.split.2x1.fill")
                            .font(.controlLabel)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brand.gradient, in: Capsule())
                            .shadow(color: Color.brand.opacity(0.35), radius: 14, x: 0, y: 8)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    addMenu
                        .padding(.trailing, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.md)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectionForCompare.count)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Add a Photo", isPresented: $showingPhotoSourceDialog, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showingCamera = true }
                }
                Button("Choose from Library") { showingPhotoPicker = true }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photosPickerItem, matching: .images)
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
            .sheet(item: $detailPhoto) { photo in
                PhotoDetailView(photo: photo, url: appData.signedPhotoURLs[photo.storagePath])
            }
            .alert(
                "Couldn't Add Photo",
                isPresented: Binding(
                    get: { appData.photoUploadErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { appData.photoUploadErrorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appData.photoUploadErrorMessage ?? "")
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
            // A plain Button here, not a nested PhotosPicker -- PhotosPicker
            // presented directly as a Menu item is unreliable (the Menu's
            // own dismissal can swallow the tap before the picker's sheet
            // ever presents). Triggering it via the decoupled
            // .photosPicker(isPresented:) modifier below is the reliable
            // path.
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.brand.gradient, in: Circle())
                .shadow(color: Color.brand.opacity(0.35), radius: 14, x: 0, y: 8)
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

// MARK: - TEMP DIAGNOSTIC (remove before shipping)

private struct PhotoThumbnail: View {
    let photo: ProgressPhoto
    let url: URL?
    let isSelected: Bool
    let onShowDetail: () -> Void

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
                    .font(.chipLabel)
                    .foregroundStyle(.white)
                Spacer()
                if let score = photo.skinScore {
                    Text("\(Int(score.rounded()))")
                        .font(.chipLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brand.opacity(0.85), in: Capsule())
                }
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
            } else {
                Button(action: onShowDetail) {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

private struct WeeklyDigestCard: View {
    let digest: WeeklyDigestEngine.Digest

    /// Three stat columns side by side stop fitting once the reader turns
    /// text size up -- at accessibility sizes even "5/7" wrapped mid-value.
    /// Past that threshold the columns stack instead of shrinking.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var scoreDeltaText: String? {
        guard let delta = digest.scoreDelta, abs(delta) >= 1 else { return nil }
        return "\(delta > 0 ? "+" : "")\(Int(delta.rounded())) this week"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("THIS WEEK")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            AnyLayout(
                dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.lg))
            ) {
                statColumn(
                    value: "\(digest.daysLogged)/7",
                    label: "Days Logged",
                    icon: "checkmark.circle.fill"
                )
                statColumn(
                    value: "\(digest.streak)",
                    label: "Day Streak",
                    icon: "flame.fill"
                )
                if let latestScore = digest.latestScore {
                    statColumn(
                        value: "\(Int(latestScore.rounded()))",
                        label: "Skin Score",
                        icon: "sparkles",
                        caption: scoreDeltaText
                    )
                }
            }

            if let product = digest.mostConsistentProduct {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.brand)
                    Text("Most used: **\(product.name)** — \(digest.mostConsistentUseCount)x")
                        .font(.rowSubtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !digest.productsNeedingReorder.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("Running low: \(digest.productsNeedingReorder.map(\.name).joined(separator: ", "))")
                        .font(.rowSubtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private func statColumn(value: String, label: String, icon: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote)
                Text(value)
                    .font(.metric)
            }
            .foregroundStyle(Color.brand)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let caption {
                let tint: Color = (digest.scoreDelta ?? 0) > 0 ? .green : ((digest.scoreDelta ?? 0) < 0 ? .red : .secondary)
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PerZoneProgressCard: View {
    let zoneProgress: [PerZoneProgressEngine.ZoneProgress]

    /// Worse zones first, so the one most worth attention leads.
    private var sorted: [PerZoneProgressEngine.ZoneProgress] {
        zoneProgress.sorted { $0.latestSeverity > $1.latestSeverity }
    }

    private var maxSeverity: Int {
        max(zoneProgress.map { max($0.earliestSeverity, $0.latestSeverity) }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("PER-ZONE PROGRESS")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(sorted) { zone in
                    zoneRow(zone)
                }
            }

            Text("Flagged area per face zone, from your first scan to your latest.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private func zoneRow(_ zone: PerZoneProgressEngine.ZoneProgress) -> some View {
        // GeometryReader is notorious for claiming far more width than its
        // container actually has when the proposal chain down to it isn't
        // explicitly pinned -- the card's own outer frame(maxWidth: .infinity)
        // doesn't automatically reach through the ForEach and this row's own
        // VStack, so this row needs its own explicit width constraint too.
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(zone.zone.label)
                    .font(.rowSubtitle.weight(.medium))
                Spacer()
                if zone.delta != 0 {
                    Label(
                        "\(abs(zone.delta))",
                        systemImage: zone.delta < 0 ? "arrow.down.right" : "arrow.up.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(zone.delta < 0 ? .green : .red)
                } else {
                    Text("No change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.subtleBorder)
                    Capsule()
                        .fill(severityTint(for: zone).gradient)
                        .frame(width: geometry.size.width * severityFraction(for: zone))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func severityFraction(for zone: PerZoneProgressEngine.ZoneProgress) -> Double {
        min(Double(zone.latestSeverity) / Double(maxSeverity), 1)
    }

    /// The bar's length is *how much is still flagged* -- longer means
    /// worse. Painting that in brand green put a nearly-full green bar
    /// directly beneath a red "got worse" arrow, so the row's two halves
    /// contradicted each other. Warming the tint as the bar grows makes
    /// length and color say the same thing.
    private func severityTint(for zone: PerZoneProgressEngine.ZoneProgress) -> Color {
        switch severityFraction(for: zone) {
        case ..<0.34: return .brand
        case ..<0.67: return .orange
        default: return .red
        }
    }
}

private struct SkinScoreTrendCard: View {
    /// Oldest first; every element has a non-nil skinScore (the caller
    /// filters before constructing this).
    let photos: [ProgressPhoto]
    let products: [Product]

    private var latestScore: Double { photos.last?.skinScore ?? 0 }
    private var delta: Double { latestScore - (photos.first?.skinScore ?? latestScore) }

    private struct Milestone: Identifiable {
        let id: Date
        let date: Date
        let productNames: [String]
    }

    /// Products opened within the chart's visible date range, grouped by
    /// calendar day -- several added in the same sitting (common right
    /// after setting up the app) collapse into one marker instead of
    /// stacking indistinguishable lines on top of each other. `openedDate`
    /// (not a creation timestamp) is used deliberately: it's the
    /// user-editable "when I actually started this" field already shown in
    /// ProductEditView, which is the honest signal here, not "when I got
    /// around to entering it into the app."
    private var milestones: [Milestone] {
        guard let start = photos.first?.timestamp, let end = photos.last?.timestamp, start <= end else { return [] }
        let calendar = Calendar.current
        let inRange = products.filter { (start...end).contains($0.openedDate) }
        let grouped = Dictionary(grouping: inRange) { calendar.startOfDay(for: $0.openedDate) }
        return grouped
            .map { day, products in Milestone(id: day, date: day, productNames: products.map(\.name)) }
            .sorted { $0.date < $1.date }
    }

    /// Explicit x-axis tick dates, taken from the days the photos were
    /// actually taken. Letting Charts choose (`.automatic`) placed ticks at
    /// sub-day positions that formatted to the same string, rendering a
    /// visibly duplicated axis ("Aug 28 ... Aug 28"); deriving them from
    /// distinct calendar days makes every label unique by construction.
    /// Capped at three so a long history doesn't crowd a 120pt-tall plot.
    private var axisDates: [Date] {
        let calendar = Calendar.current
        let days = Set(photos.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
        guard days.count > 2 else { return days }
        return [days[0], days[days.count / 2], days[days.count - 1]]
    }

    /// The plotted date range, widened by a margin at each end. Without it
    /// the final tick sits flush against the plot's right edge and its
    /// label is clipped by the card ("Aug 29" rendering as "A"), since axis
    /// labels are centered on their tick.
    private var paddedDomain: ClosedRange<Date> {
        guard let first = photos.first?.timestamp, let last = photos.last?.timestamp else {
            return Date.now...Date.now
        }
        // A day minimum, so a single-day span still gets breathing room.
        let margin = max(last.timeIntervalSince(first) * 0.12, 43_200)
        return first.addingTimeInterval(-margin)...last.addingTimeInterval(margin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("Skin Score Trend")
                    .font(.cardTitle)
                Spacer()
                Text("\(Int(latestScore.rounded()))")
                    .font(.metricLarge)
                    .foregroundStyle(Color.brand)
                if abs(delta) >= 1 {
                    Label(
                        "\(delta > 0 ? "+" : "")\(Int(delta.rounded()))",
                        systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta > 0 ? .green : .red)
                }
            }

            Chart {
                ForEach(photos) { photo in
                    LineMark(
                        x: .value("Date", photo.timestamp),
                        y: .value("Score", photo.skinScore ?? 0)
                    )
                    .foregroundStyle(Color.brand)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", photo.timestamp),
                        y: .value("Score", photo.skinScore ?? 0)
                    )
                    .foregroundStyle(Color.brand)
                }

                ForEach(milestones) { milestone in
                    RuleMark(x: .value("Started", milestone.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: paddedDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100])
            }
            .frame(height: 120)
            // Purely decorative -- no tap/selection -- and Swift Charts
            // attaches its own gesture recognizer inside the view's bounds
            // by default, which can fight the parent ScrollView's own pan
            // gesture. Disabling hit testing lets every touch pass straight
            // through to the ScrollView instead.
            .allowsHitTesting(false)

            if !milestones.isEmpty {
                milestoneCaption
            }

            // The score's own real-world accuracy is modest (see
            // SkinScanService) -- framed as a direction to watch, not a
            // number to obsess over week to week.
            Text("Trend across your scanned photos — a directional read, not a precise measurement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// The dashed lines on the chart are position only -- cramming product
    /// names directly onto a 120pt-tall plot reads as clutter fast once
    /// more than one shows up in the same window, so the actual detail
    /// lives in this compact list instead. Capped at 4 lines; a burst of
    /// more than that (e.g. everything added on day one) collapses to a
    /// count rather than listing every name.
    private var milestoneCaption: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(milestones.prefix(4)) { milestone in
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 10, height: 1)
                    Text("Started \(milestone.productNames.joined(separator: ", ")) — \(milestone.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if milestones.count > 4 {
                Text("+ \(milestones.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
