//
//  PhotoDetailView.swift
//  Regimen
//

import StoreKit
import SwiftUI
import os

/// Full-size photo plus its on-device skin scan: highlighted problem
/// patches drawn over the photo and a single 0-100 skin score. The scan
/// runs entirely on-device (see `SkinScanService`) — the photo is never
/// sent anywhere to be scored.
struct PhotoDetailView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// The overlay saved by a previous scan, downloaded on appear. Lets an
    /// already-scanned photo show its highlights again without re-running
    /// the models -- which a free account, having spent its one scan,
    /// cannot do at all.
    @State private var storedOverlay: UIImage?
    @State private var showingFreeScanConfirmation = false
    @State private var showingDeleteConfirmation = false
    /// Non-nil for one render after a scan finishes, to fire a haptic.
    @State private var scanFeedback: ScanFeedback?
    /// Drives the count-up. Starts at zero and is animated to the real
    /// score once it's known, so the number the user waited for arrives as
    /// a reveal rather than as text that was simply already there.
    @State private var revealedScore: Double = 0
    @State private var noteDraft = ""
    @State private var isEditingNote = false
    @FocusState private var noteFieldFocused: Bool

    private enum ScanFeedback {
        case success
        case error
    }

    /// Re-reads from AppData rather than trusting the `photo` passed in,
    /// so the persisted score appears immediately after a scan without
    /// re-opening the sheet.
    private var currentPhoto: ProgressPhoto {
        appData.progressPhotos.first(where: { $0.id == photo.id }) ?? photo
    }

    /// The most recent scan taken *before* this photo, to tell "your skin
    /// improved" from "this is your first scan". Nil when there's nothing
    /// earlier to compare against.
    private var previousScan: ProgressPhoto? {
        appData.progressPhotos
            .filter { $0.id != photo.id && $0.timestamp < photo.timestamp && $0.skinScore != nil }
            .max { $0.timestamp < $1.timestamp }
    }

    private var previousScore: Double? { previousScan?.skinScore }

    /// The movement since the last scan, which is the number people
    /// actually care about -- it was already being computed to decide
    /// whether to ask for an App Store review, but never shown to the
    /// person whose skin it describes.
    ///
    /// Nil below a full point: this model's real-world accuracy is modest
    /// (MAE ~9, see `SkinScanService`), so dressing up sub-point drift as
    /// progress would be inventing a result.
    private func scoreChange(from score: Double) -> (text: String, isImprovement: Bool)? {
        guard let previous = previousScan, let baseline = previous.skinScore else { return nil }
        let delta = score - baseline
        guard abs(delta) >= 1 else { return nil }
        let sign = delta > 0 ? "+" : ""
        let date = previous.timestamp.formatted(.dateTime.month(.abbreviated).day())
        return ("\(sign)\(Int(delta.rounded())) since \(date)", delta > 0)
    }

    /// A plain-language lead so the card opens with a verdict rather than
    /// leaving the reader to work out whether 71 is good.
    private func headline(for score: Double) -> String {
        guard let result = scanResult else {
            // Viewing an already-scored photo without re-running: the score
            // persists but the findings don't (see `AppData.scanPhoto`), so
            // there's no count to quote.
            return qualitativeLead(for: score)
        }
        let total = result.counts.values.reduce(0, +)
        guard total > 0 else { return "Nothing notable flagged." }
        return "\(qualitativeLead(for: score)), \(total) area\(total == 1 ? "" : "s") flagged."
    }

    private func qualitativeLead(for score: Double) -> String {
        switch score {
        case 80...: "Looking clear"
        case 60..<80: "Mostly clear"
        case 40..<60: "Some things to work on"
        default: "Plenty to work on"
        }
    }

    private var scanButtonTitle: String {
        guard currentPhoto.skinScore == nil, scanResult == nil else { return "Re-scan" }
        if !appData.isPremium && !appData.hasUsedFreeScan { return "Try Your Free Scan" }
        return "Scan Skin"
    }

    // MARK: - Displayed scan
    //
    // A scan shown on screen comes from one of two places: the one just
    // run (full fidelity, in memory) or the one saved with the photo. The
    // stored path is what makes a scan survive closing the sheet -- before
    // it existed, a free user's single scan was gone the moment they
    // dismissed, with re-scanning locked behind the paywall.

    private var displayedOverlay: UIImage? {
        scanResult?.overlay ?? storedOverlay
    }

    private var displayedFaceRect: CGRect? {
        scanResult?.faceRect ?? currentPhoto.faceRect
    }

    /// Per-kind counts from the fresh scan, or rebuilt from the saved
    /// per-zone rows.
    private var displayedCounts: [FindingKind: Int] {
        scanResult?.counts ?? appData.storedFindingCounts(for: currentPhoto)
    }

    /// Whether there are results on screen at all -- the one value the
    /// sequenced reveal keys off, so every card animates from the same
    /// change rather than each from its own.
    private var hasResults: Bool {
        scanResult != nil || currentPhoto.hasStoredScan
    }

    private var displayedAttributes: [SkinAttribute] {
        scanResult?.attributes ?? currentPhoto.skinAttributes
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Delete Photo", systemImage: "trash", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Photo options")
                }
            }
            .confirmationDialog(
                "Delete this photo?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Photo", role: .destructive) {
                    Task {
                        await appData.deletePhoto(currentPhoto)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the photo, its scan and its score for good. Your other scans and your streak are untouched.")
            }
            .task {
                await loadImage()
                await restoreStoredScan()
            }
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
            .sensoryFeedback(trigger: scanFeedback) { _, feedback in
                switch feedback {
                case .success: .success
                case .error: .error
                case nil: nil
                }
            }
            .confirmationDialog(
                "Use your free scan?",
                isPresented: $showingFreeScanConfirmation,
                titleVisibility: .visible
            ) {
                Button("Scan This Photo") { runScan() }
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("You get one free scan. Make sure this is a well-lit, front-facing photo before using it.")
            }
            .sheet(item: $routineRequest) { request in
                RoutineBuilderView(counts: displayedCounts, profile: request.profile)
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

                    if let overlay = displayedOverlay, let faceRect = displayedFaceRect {
                        Image(uiImage: overlay)
                            .resizable()
                            .interpolation(.medium)
                            .frame(
                                width: faceRect.width * layout.size.width,
                                height: faceRect.height * layout.size.height
                            )
                            .offset(
                                x: layout.origin.x + faceRect.minX * layout.size.width,
                                y: layout.origin.y + faceRect.minY * layout.size.height
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
        .motion(Motion.card, value: displayedOverlay != nil)
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
                        AnimatedNumber(value: revealedScore)
                    }
                    ProgressGauge(fraction: revealedScore / 100, tint: Color.brand)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(headline(for: score))
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                            // Wraps rather than truncating: the headline and
                            // the delta together overflow a narrow card, and
                            // the delta is the half that must stay whole.
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let change = scoreChange(from: score) {
                            Label(change.text, systemImage: change.isImprovement ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(change.isImprovement ? .green : .red)
                                .fixedSize()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
                .task(id: score) {
                    // Re-run whenever the score changes, so a re-scan counts
                    // from the old value to the new one instead of jumping.
                    guard !reduceMotion else {
                        revealedScore = score
                        return
                    }
                    withAnimation(Motion.reveal) { revealedScore = score }
                }
            }

            noteCard

            if currentPhoto.hasStoredScan || scanResult != nil {
                findingsCard(displayedCounts)
                .sequencedReveal(0, trigger: hasResults)
            }

            if !displayedAttributes.isEmpty {
                attributesCard(displayedAttributes)
                .sequencedReveal(1, trigger: hasResults)
            }

            if !categoryRecommendations.isEmpty {
                categoryCardsSection
                .sequencedReveal(2, trigger: hasResults)
            }

            if let plan, !plan.sections.isEmpty {
                planCard(plan)
                .sequencedReveal(3, trigger: hasResults)
            }

            if let scanErrorMessage {
                scanErrorCard(scanErrorMessage)
            }

            Button(action: scanButtonTapped) {
                if isScanning {
                    // A bare spinner gives no sense of what's happening or
                    // that it's happening locally, which is the one thing
                    // worth knowing while waiting on a photo of your face.
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView().tint(.white)
                        Text("Analyzing on device…")
                    }
                } else {
                    Label(
                        scanButtonTitle,
                        systemImage: "sparkles"
                    )
                }
            }
            .buttonStyle(.primary)
            .disabled(isScanning || loadedImage == nil)
            .motion(Motion.toggle, value: isScanning)

            if scanResult == nil {
                Text("Runs on-device. This photo is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Set expectations before they tap, not after -- finding
                // out a scan was "the free one" only once a second attempt
                // gets blocked would feel like a bait and switch.
                if !appData.isPremium && !appData.hasUsedFreeScan {
                    Text("Your first scan is free. Premium unlocks the rest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    /// A place to say what was going on. The timeline is a row of faces
    /// that all look broadly similar months later; "started tretinoin" or
    /// "week of bad sleep" beside one is what turns it into a record you
    /// can actually reason about.
    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("NOTE")
                    .font(.sectionLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isEditingNote {
                    Button(currentPhoto.note == nil ? "Add" : "Edit") {
                        noteDraft = currentPhoto.note ?? ""
                        isEditingNote = true
                        noteFieldFocused = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                }
            }

            if isEditingNote {
                TextField("What was going on?", text: $noteDraft, axis: .vertical)
                    .font(.bodyText)
                    .lineLimit(2...5)
                    .focused($noteFieldFocused)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Color.appBackground)
                    )
                HStack {
                    Button("Cancel") {
                        isEditingNote = false
                        noteFieldFocused = false
                    }
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        Task { await appData.setNote(noteDraft, on: currentPhoto) }
                        isEditingNote = false
                        noteFieldFocused = false
                    }
                    .font(.rowSubtitle.weight(.semibold))
                    .foregroundStyle(Color.brand)
                }
            } else if let note = currentPhoto.note, !note.isEmpty {
                Text(note)
                    .font(.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing noted for this photo.")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// A failed scan used to be a single grey sentence with nothing to act
    /// on -- which is the worst moment in the flow to leave someone
    /// stranded, since "no face detected" is almost always fixable by
    /// retaking the photo slightly differently. The fix belongs next to the
    /// failure, not buried in an empty-state string on another screen.
    private func scanErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Scan Didn't Run", systemImage: "exclamationmark.triangle.fill")
                .font(.cardTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.bodyText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.captureTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.brand)
                            .padding(.top, 3)
                        Text(tip)
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// What the segmentation model was actually trained on (well-lit,
    /// front-facing head shots -- see `SkinScanService`), written as things
    /// a person can do rather than as model constraints.
    private static let captureTips = [
        "Face the camera straight on, whole face in frame.",
        "Even, bright light. No harsh shadows or backlight.",
        "No makeup, filters, or heavy edits.",
        "Hold still so the photo stays sharp.",
    ]

    private func findingsCard(_ counts: [FindingKind: Int]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("SPOTTED")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            if counts.isEmpty {
                Text("Nothing notable. Skin looks clear.")
                    .font(.bodyText)
            } else {
                ForEach(FindingKind.allCases, id: \.self) { kind in
                    if let count = counts[kind] {
                        HStack(spacing: Theme.Spacing.sm) {
                            Circle().fill(kind.tint).frame(width: 8, height: 8)
                            Text("\(count) \(count == 1 ? kind.singular : kind.plural)")
                                .font(.bodyText)
                        }
                    }
                }
            }

            Text("Rough estimates from the photo, not a diagnosis.")
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

            Text("Whole-face signals from a separate model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }

    /// Ordered strongest-evidence-first by `RecommendationEngine`, and laid
    /// out as rows rather than the three-column icon grid this replaced.
    /// The grid looked tidier but had room for a name and nothing else --
    /// no space for *why* a category came up, whether it clashes with
    /// something already owned, or whether it's one to ease into. Those are
    /// the whole point of a recommendation, so the layout gave way to them.
    private var categoryCardsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("WHAT TO USE")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(categoryRecommendations) { recommendation in
                    CategoryRow(recommendation: recommendation) {
                        selectedCategoryTag = recommendation.tag
                    }
                }
            }

            Text("Tap to browse the catalog. A checkmark means you already own it.")
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

    /// Rebuilds everything a previous scan left behind, so reopening a
    /// scanned photo shows what it showed the first time rather than a bare
    /// number. Skipped once a fresh scan is on screen -- that's strictly
    /// better data.
    private func restoreStoredScan() async {
        guard scanResult == nil, currentPhoto.hasStoredScan else { return }

        let counts = appData.storedFindingCounts(for: currentPhoto)
        let attributes = currentPhoto.skinAttributes
        if !counts.isEmpty || !attributes.isEmpty {
            plan = PlanEngine.plan(
                counts: counts,
                attributes: attributes,
                ownedProducts: appData.products
            )
            categoryRecommendations = RecommendationEngine.categoryRecommendations(
                counts: counts,
                attributes: attributes,
                ownedProducts: appData.products,
                profile: appData.effectiveSkinProfile
            )
        }

        guard storedOverlay == nil,
              let overlayPath = currentPhoto.overlayPath,
              let overlayURL = appData.signedPhotoURLs[overlayPath],
              let (data, _) = try? await URLSession.shared.data(from: overlayURL)
        else { return }
        storedOverlay = UIImage(data: data)
    }

    /// Entry point for the scan button. Splits into three cases: no scans
    /// left (paywall), the one free scan still unspent (confirm first), or
    /// premium (just go).
    private func scanButtonTapped() {
        guard appData.canRunFreeScan else {
            Analytics.track(.paywallShown(source: .scan))
            showingPaywall = true
            return
        }
        // Spending the single free scan silently on whatever photo happened
        // to be open -- a blurry test shot, say -- burned the one chance
        // this user had to see the feature work, at exactly the moment the
        // app is trying to earn a subscription.
        if !appData.isPremium && !appData.hasUsedFreeScan {
            showingFreeScanConfirmation = true
            return
        }
        runScan()
    }

    private func runScan() {
        guard let loadedImage else { return }
        guard appData.canRunFreeScan else {
            showingPaywall = true
            return
        }
        isScanning = true
        let isFreeScan = !appData.isPremium
        Analytics.track(.scanStarted(isFree: isFreeScan))
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
                // The quiz's answers are the only source of how this skin
                // actually *behaves* -- without them the same cards would
                // push pure vitamin C at someone whose skin stings. Falls
                // back to `SkinProfile`'s conservative defaults when the
                // quiz hasn't been taken yet.
                categoryRecommendations = RecommendationEngine.categoryRecommendations(
                    for: result,
                    ownedProducts: appData.products,
                    profile: appData.effectiveSkinProfile
                )
                storedOverlay = nil
                scanFeedback = .success
                Analytics.track(.scanCompleted(isFree: isFreeScan))
                await appData.markFreeScanUsed()

                if let baseline {
                    askForReview(moment: .skinScoreImproved(delta: result.score - baseline))
                }
            } catch SkinScanError.noFaceDetected {
                scanErrorMessage = "Couldn't find a face in this photo. Scanning works best on a well-lit, front-facing photo."
                scanFeedback = .error
                Analytics.track(.scanFailed(reason: .noFace))
            } catch {
                AppLog.scan.error("scan failed: \(error.localizedDescription, privacy: .public)")
                scanErrorMessage = "Something went wrong running the scan."
                scanFeedback = .error
                Analytics.track(.scanFailed(reason: .other))
            }
        }
    }

    private func buildRoutine() {
        guard appData.isPremium else {
            Analytics.track(.paywallShown(source: .routineBuilder))
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

private struct CategoryRow: View {
    let recommendation: RecommendationEngine.CategoryRecommendation
    let action: () -> Void

    /// Everything after the name, read out as one sentence rather than as
    /// four separate unlabelled fragments.
    private var accessibilityDescription: String {
        var parts = [recommendation.tag.rawValue, recommendation.reason]
        if let owned = recommendation.ownedProductName {
            parts.append("Already in your cabinet: \(owned).")
        }
        if recommendation.needsGentleStart {
            parts.append("Ease into this one.")
        }
        if let warning = recommendation.conflictWarning {
            parts.append(warning)
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: recommendation.tag.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(recommendation.tag.rawValue)
                            .font(.rowTitle)
                            .foregroundStyle(.primary)
                        if recommendation.ownedProductName != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.green)
                        }
                    }

                    Text(recommendation.reason)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if recommendation.needsGentleStart {
                        Label("Ease in, 2x a week to start", systemImage: "tortoise.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let warning = recommendation.conflictWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }
}
