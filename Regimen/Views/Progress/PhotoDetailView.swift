//
//  PhotoDetailView.swift
//  Regimen
//

import StoreKit
import SwiftUI

/// Full-size photo plus its on-device skin scan: highlighted problem
/// patches drawn over the photo and a single 0-100 skin score. The scan
/// runs entirely on-device (see `SkinScanService`) — the photo is never
/// sent anywhere to be scored.
struct PhotoDetailView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    let photo: ProgressPhoto
    let url: URL?

    @State private var loadedImage: UIImage?
    @State private var isScanning = false
    @State private var scanResult: SkinScanResult?
    @State private var scanErrorMessage: String?
    @State private var plan: PlanEngine.Plan?
    @State private var categoryRecommendations: [RecommendationEngine.CategoryRecommendation] = []
    @State private var selectedCategoryTag: ConflictTag?
    @State private var showingPaywall = false
    @State private var showingRoutineQuiz = false
    /// Held while the quiz sheet is still dismissing, then promoted to
    /// `routineRequest` in its onDismiss -- presenting the second sheet
    /// directly from the quiz's completion races its dismissal and can
    /// leave neither sheet on screen.
    @State private var pendingProfile: SkinProfile?
    @State private var routineRequest: BuiltRoutineRequest?

    /// Re-reads from AppData rather than trusting the `photo` passed in,
    /// so the persisted score appears immediately after a scan without
    /// re-opening the sheet.
    private var currentPhoto: ProgressPhoto {
        appData.progressPhotos.first(where: { $0.id == photo.id }) ?? photo
    }

    /// The score from the most recent scan taken *before* this photo, to
    /// tell "your skin improved" from "this is your first scan". Nil when
    /// there's nothing earlier to compare against.
    private var previousScore: Double? {
        appData.progressPhotos
            .filter { $0.id != photo.id && $0.timestamp < photo.timestamp && $0.skinScore != nil }
            .max { $0.timestamp < $1.timestamp }?
            .skinScore
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    imageWithOverlay
                        .padding(.horizontal, Theme.Spacing.lg)

                    scanSection
                }
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(photo.timestamp.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadImage() }
            .sheet(item: $selectedCategoryTag) { tag in
                CategoryProductsView(tag: tag)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingRoutineQuiz, onDismiss: presentBuiltRoutine) {
                RoutineQuizView { profile in
                    pendingProfile = profile
                    showingRoutineQuiz = false
                }
            }
            .sheet(item: $routineRequest) { request in
                RoutineBuilderView(counts: scanResult?.counts ?? [:], profile: request.profile)
            }
        }
    }

    // MARK: - Photo + overlay

    @ViewBuilder
    private var imageWithOverlay: some View {
        GeometryReader { geometry in
            if let loadedImage {
                let layout = imageLayout(imageSize: loadedImage.size, containerSize: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()

                    if let result = scanResult, let overlay = result.overlay {
                        Image(uiImage: overlay)
                            .resizable()
                            .interpolation(.medium)
                            .frame(
                                width: result.faceRect.width * layout.size.width,
                                height: result.faceRect.height * layout.size.height
                            )
                            .offset(
                                x: layout.origin.x + result.faceRect.minX * layout.size.width,
                                y: layout.origin.y + result.faceRect.minY * layout.size.height
                            )
                            .transition(.opacity)
                    }
                }
            } else {
                Rectangle().fill(Color.subtleBorder)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: scanResult?.overlay != nil)
    }

    /// scaledToFit() centers the image without distorting it, which can
    /// leave empty space on two sides — the overlay must be placed against
    /// the photo's actual on-screen rect, not the container's bounds.
    private func imageLayout(imageSize: CGSize, containerSize: CGSize) -> (origin: CGPoint, size: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return (.zero, containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (containerSize.width - displaySize.width) / 2, y: (containerSize.height - displaySize.height) / 2)
        return (origin, displaySize)
    }

    // MARK: - Score + findings

    @ViewBuilder
    private var scanSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let score = scanResult?.score ?? currentPhoto.skinScore {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Skin Score")
                            .font(.cardTitle)
                        Spacer()
                        Text("\(Int(score.rounded()))")
                            .font(.metricLarge)
                            .foregroundStyle(Color.brand)
                    }
                    ProgressGauge(fraction: score / 100, tint: Color.brand)
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
            }

            if let result = scanResult {
                findingsCard(result)
            }

            if let result = scanResult, !result.attributes.isEmpty {
                attributesCard(result.attributes)
            }

            if !categoryRecommendations.isEmpty {
                categoryCardsSection
            }

            if let plan, !plan.sections.isEmpty {
                planCard(plan)
            }

            if let scanErrorMessage {
                Text(scanErrorMessage)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: runScan) {
                if isScanning {
                    ProgressView().tint(.white)
                } else {
                    Label(
                        currentPhoto.skinScore == nil && scanResult == nil ? "Scan Skin" : "Re-scan",
                        systemImage: "sparkles"
                    )
                }
            }
            .buttonStyle(.primary)
            .disabled(isScanning || loadedImage == nil)

            if scanResult == nil {
                Text("Runs fully on-device — this photo is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func findingsCard(_ result: SkinScanResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("SPOTTED")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            if result.counts.isEmpty {
                Text("Nothing notable — skin looks clear.")
                    .font(.bodyText)
            } else {
                ForEach(FindingKind.allCases, id: \.self) { kind in
                    if let count = result.counts[kind] {
                        HStack(spacing: Theme.Spacing.sm) {
                            Circle().fill(kind.tint).frame(width: 8, height: 8)
                            Text("\(count) \(count == 1 ? kind.singular : kind.plural)")
                                .font(.bodyText)
                        }
                    }
                }
            }

            Text("Highlighted areas are rough estimates from the photo, not a diagnosis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private func attributesCard(_ attributes: [SkinAttribute]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ALSO NOTICED")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            ForEach(attributes, id: \.self) { attribute in
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(Color.brand.opacity(0.5)).frame(width: 8, height: 8)
                    Text(attribute.label)
                        .font(.bodyText)
                }
            }

            Text("Whole-face signals from a smaller, separate model — treat these as softer hints than the highlighted areas above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    private var categoryCardsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WHAT TO USE")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            // Three fixed columns, top-aligned. A GridItem defaults to
            // .center, so a two-line label ("Exfoliating Acid") made its
            // cell taller and vertically re-centered its one-line
            // neighbours -- leaving the icons on a row sitting at
            // different heights.
            LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(categoryRecommendations) { recommendation in
                    CategoryCard(recommendation: recommendation) {
                        selectedCategoryTag = recommendation.tag
                    }
                }
            }

            Text("Tap a category to browse the catalog. A checkmark means it's already in your cabinet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Building a routine is the natural next step from "here's what
            // to use", so it belongs in this card rather than floating
            // underneath it as an unattached control.
            Divider()
                .padding(.vertical, Theme.Spacing.xs)

            Button(action: buildRoutine) {
                Label("Build My Routine", systemImage: "wand.and.stars")
            }
            .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// Three even columns, explicitly top-aligned so every icon in a row
    /// lands at the same height regardless of how many lines its label
    /// wraps to.
    private var categoryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm, alignment: .top), count: 3)
    }

    private func planCard(_ plan: PlanEngine.Plan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("YOUR PLAN")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            ForEach(plan.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.rowTitle)
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(Color.brand.opacity(0.6))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(item)
                                .font(.bodyText)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    // MARK: - Actions

    private func loadImage() async {
        guard let url else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        loadedImage = UIImage(data: data)
    }

    private func runScan() {
        guard let loadedImage else { return }
        guard appData.isPremium else {
            showingPaywall = true
            return
        }
        isScanning = true
        scanErrorMessage = nil
        plan = nil
        categoryRecommendations = []
        Task {
            defer { isScanning = false }
            do {
                // Captured before the scan writes the new score, so the
                // comparison is against the previous scan rather than this
                // one.
                let baseline = previousScore
                let result = try await appData.scanPhoto(currentPhoto, image: loadedImage)
                scanResult = result
                plan = PlanEngine.plan(for: result, ownedProducts: appData.products)
                categoryRecommendations = RecommendationEngine.categoryRecommendations(for: result.counts, ownedProducts: appData.products)

                if let baseline {
                    askForReview(moment: .skinScoreImproved(delta: result.score - baseline))
                }
            } catch SkinScanError.noFaceDetected {
                scanErrorMessage = "Couldn't find a face in this photo. Scanning works best on a well-lit, front-facing photo."
            } catch {
                print("SkinScanService failed: \(error)")
                scanErrorMessage = "Something went wrong running the scan."
            }
        }
    }

    private func buildRoutine() {
        guard appData.isPremium else {
            showingPaywall = true
            return
        }
        showingRoutineQuiz = true
    }

    /// Runs once the quiz sheet has finished dismissing. Only presents the
    /// routine when the quiz was actually completed -- cancelling it leaves
    /// `pendingProfile` nil and nothing happens.
    private func presentBuiltRoutine() {
        guard let pendingProfile else { return }
        routineRequest = BuiltRoutineRequest(profile: pendingProfile)
        self.pendingProfile = nil
    }

    /// Asks only if `ReviewPromptManager` agrees. Delayed so the prompt
    /// follows the score reveal rather than landing on top of it.
    private func askForReview(moment: ReviewPromptManager.Moment) {
        guard ReviewPromptManager.shouldRequest(for: moment, usageLogs: appData.usageLogs) else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            ReviewPromptManager.recordRequested()
            requestReview()
        }
    }
}

/// Wraps a finished `SkinProfile` so it can drive `.sheet(item:)`. The
/// fresh id per request is what makes re-running the quiz present a newly
/// built routine rather than reusing the previous sheet.
private struct BuiltRoutineRequest: Identifiable {
    let id = UUID()
    let profile: SkinProfile
}

private struct CategoryCard: View {
    let recommendation: RecommendationEngine.CategoryRecommendation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: recommendation.tag.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if recommendation.ownedProductName != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.white, Color.green)
                            .background(Circle().fill(Color.appBackground))
                            .offset(x: 7, y: -7)
                    }
                }

                Text(recommendation.tag.rawValue)
                    .font(.chipLabel)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Fills its grid column rather than pinning to a fixed 80pt,
            // which previously left the card and its column disagreeing
            // about width and the row looking unevenly spaced.
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            recommendation.ownedProductName == nil
                ? recommendation.tag.rawValue
                : "\(recommendation.tag.rawValue), already in your cabinet"
        )
    }
}
