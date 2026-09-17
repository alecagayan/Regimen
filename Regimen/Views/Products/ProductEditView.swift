//
//  ProductEditView.swift
//  Regimen
//

import SwiftUI

/// Add/edit form for a single `Product`. Passing `nil` creates a new
/// product on save; passing an existing `Product` edits it in place.
struct ProductEditView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss

    let product: Product?
    /// Pre-fills a new (non-editing) form, e.g. from `RoutineBuilderView`'s
    /// "Add to Cabinet" — same fields `CatalogPickerView`'s onSelect sets.
    var prefillCatalogItem: CatalogProduct?
    var prefillRoutineTime: RoutineTime?
    /// Set by `RoutineBuilderView` so a suggestion that says "ease in"
    /// arrives with that schedule already filled in rather than as a daily
    /// product the user has to know to change.
    var prefillFrequency: ProductFrequency?

    @State private var name = ""
    @State private var brand = ""
    @State private var routineTime: RoutineTime = .am
    @State private var layerCategory: LayerCategory = .treatment
    @State private var applicationOrder = 1
    @State private var conflictTags: Set<ConflictTag> = []
    @State private var sizeInML: Double = 30
    @State private var typicalDoseML: Double = LayerCategory.treatment.defaultDoseML
    @State private var openedDate: Date = .now
    @State private var showingCatalogPicker = false
    @State private var showingBarcodeScanner = false
    @State private var isLookingUpBarcode = false
    @State private var barcodeMessage: String?
    @State private var ingredients: [String] = []
    @State private var usedBarcode = false
    @State private var usedCatalog = false
    /// Size, dose and order-within-step are collapsed by default for a new
    /// product. They exist for depletion prediction, which a first-time
    /// user doesn't yet know they want -- and a ten-field form is a lot to
    /// put between someone and their first working screen. Always expanded
    /// when editing, where the user came specifically to change something.
    @State private var showingAdvanced = false
    @State private var frequency: ProductFrequency = .daily
    @State private var monthsAfterOpening: Int = 0

    private var isEditing: Bool { product != nil }

    /// Where this product came from, for the activation funnel. Inferred
    /// from how the form was filled rather than passed down through every
    /// call site.
    private var addSource: Analytics.ProductSource {
        if prefillFrequency != nil { return .routineBuilder }
        if usedBarcode { return .barcode }
        if prefillCatalogItem != nil || usedCatalog { return .catalog }
        return .manual
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Button {
                            showingBarcodeScanner = true
                        } label: {
                            if isLookingUpBarcode {
                                HStack {
                                    ProgressView()
                                    Text("Looking it up…")
                                }
                            } else {
                                Label("Scan Barcode", systemImage: "barcode.viewfinder")
                            }
                        }
                        .disabled(isLookingUpBarcode)

                        Button {
                            showingCatalogPicker = true
                        } label: {
                            Label("Choose from Catalog", systemImage: "magnifyingglass")
                        }
                    } footer: {
                        if let barcodeMessage {
                            Text(barcodeMessage)
                        }
                    }
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Brand", text: $brand)
                }
                Section {
                    Picker("Time", selection: $routineTime) {
                        ForEach(RoutineTime.allCases) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                    Picker("Step", selection: $layerCategory) {
                        ForEach(LayerCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .onChange(of: layerCategory) { _, newValue in
                        // Only for a brand-new product: re-picking the step
                        // updates the suggested dose. Editing an existing
                        // product never silently overwrites a dose the user
                        // may have already corrected.
                        guard !isEditing else { return }
                        typicalDoseML = newValue.defaultDoseML
                    }
                    frequencyPicker
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Step sets the overall order: cleanser, then treatments, then moisturizer.")
                }
                Section {
                    conflictTagGrid
                    if !undeclaredDerivedTags.isEmpty {
                        derivedTagSuggestion
                    }
                } header: {
                    Text("Active Ingredients")
                } footer: {
                    Text("Select every one that applies. This is what the Routine tab checks for conflicts.")
                }
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text("Size")
                            Spacer()
                            TextField("mL", value: $sizeInML, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("mL").foregroundStyle(.secondary)
                        }
                        // Typing an exact millilitre figure means reading
                        // the back of the bottle. These cover most of what
                        // skincare actually ships in.
                        sizePresets
                    }

                    Picker("Use within", selection: $monthsAfterOpening) {
                        Text("Not set").tag(0)
                        ForEach([3, 6, 12, 24], id: \.self) { months in
                            Text("\(months) months").tag(months)
                        }
                    }

                    if isEditing || showingAdvanced {
                        HStack {
                            Text("Amount per use")
                            Spacer()
                            TextField("mL", value: $typicalDoseML, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("mL").foregroundStyle(.secondary)
                        }
                        Stepper("Order within step: \(applicationOrder)", value: $applicationOrder, in: 1...20)
                        DatePicker("Opened", selection: $openedDate, displayedComponents: .date)
                    } else {
                        Button("More options") {
                            withAnimation { showingAdvanced = true }
                        }
                        .font(.rowSubtitle.weight(.semibold))
                    }
                } header: {
                    Text("Bottle")
                } footer: {
                    Text(
                        isEditing || showingAdvanced
                            ? "Amount per use is what each check-off counts toward running out. Adjust it if a product empties faster than predicted. \"Use within\" is the jar symbol on the packaging."
                            : "Size predicts when you'll run out. Everything else has a sensible default."
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(isEditing ? "Edit Product" : "Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: populateFields)
            .sheet(isPresented: $showingCatalogPicker) {
                CatalogPickerView { catalogItem in
                    usedCatalog = true
                    apply(catalogItem)
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView { code in
                    Task { await lookUp(barcode: code) }
                }
            }
        }
    }

    /// A wrapping grid of toggleable chips rather than a single picker --
    /// a real product often carries more than one flaggable active (a
    /// serum combining a retinoid with niacinamide, say), which a picker's
    /// one-of-many selection couldn't represent.
    /// How often this product is used. Most things are daily, so that's
    /// one tap and the rest stays out of the way until it's needed.
    @ViewBuilder
    private var frequencyPicker: some View {
        Picker("How often", selection: frequencyKindBinding) {
            Text("Every day").tag("daily")
            Text("Certain days").tag("days_of_week")
            Text("Every few days").tag("every_n_days")
        }

        switch frequency {
        case .daysOfWeek(let days):
            weekdayPicker(selected: days)
        case .everyNDays(let interval):
            Stepper("Every \(interval) days", value: intervalBinding, in: 2...14)
        case .daily:
            EmptyView()
        }
    }

    private var frequencyKindBinding: Binding<String> {
        Binding(
            get: { frequency.kindKey },
            set: { kind in
                switch kind {
                case "days_of_week":
                    // Seeds with every day selected rather than none, so the
                    // product can't silently disappear from the routine
                    // while the user is still deciding which days.
                    frequency = .daysOfWeek(Set(1...7))
                case "every_n_days":
                    frequency = .everyOtherDay
                default:
                    frequency = .daily
                }
            }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { frequency.storedIntervalDays },
            set: { frequency = .everyNDays($0) }
        )
    }

    private func weekdayPicker(selected: Set<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { weekday in
                let symbols = Calendar.current.veryShortWeekdaySymbols
                let isOn = selected.contains(weekday)
                Button {
                    var updated = selected
                    if isOn { updated.remove(weekday) } else { updated.insert(weekday) }
                    frequency = .daysOfWeek(updated)
                } label: {
                    Text(symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOn ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isOn ? Color.brand.gradient : Color.subtleBorder.opacity(0.4).gradient)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// Common skincare bottle sizes, as one-tap chips.
    private var sizePresets: some View {
        HStack(spacing: 6) {
            ForEach([15.0, 30.0, 50.0, 100.0, 200.0], id: \.self) { size in
                let isSelected = sizeInML == size
                Button {
                    sizeInML = size
                } label: {
                    Text("\(Int(size))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? Color.brand.gradient : Color.subtleBorder.opacity(0.4).gradient)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(size)) millilitres")
            }
        }
    }

    private var conflictTagGrid: some View {
        FlowLayout(spacing: Theme.Spacing.sm) {
            ForEach(ConflictTag.allCases.filter { $0 != .none }) { tag in
                let isSelected = conflictTags.contains(tag)
                Button {
                    if isSelected {
                        conflictTags.remove(tag)
                    } else {
                        conflictTags.insert(tag)
                    }
                } label: {
                    Text(tag.rawValue)
                        .font(.rowSubtitle.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(isSelected ? Color.brand.gradient : Color.subtleBorder.opacity(0.4).gradient)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Actives the ingredient list implies that aren't ticked above.
    private var undeclaredDerivedTags: [ConflictTag] {
        IngredientConflictMapper.tags(for: ingredients).filter { !conflictTags.contains($0) }
    }

    /// Offered rather than applied silently. Ticking boxes on the user's
    /// behalf when they open a product to edit it would be the app
    /// disagreeing with them without saying so -- and the ingredient list
    /// can be wrong or partial. Conflict checking already reads these via
    /// `Product.effectiveConflictTags`, so declining costs no safety; it
    /// just leaves the tag off the form.
    private var derivedTagSuggestion: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Found in the ingredients", systemImage: "sparkle.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(undeclaredDerivedTags) { tag in
                let evidence = IngredientConflictMapper.evidence(for: tag, in: ingredients)
                Button {
                    conflictTags.insert(tag)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tag.rawValue)
                                .font(.rowSubtitle.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let first = evidence.first {
                                Text(first.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        Text("Add")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brand)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.subtleBorder.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(tag.rawValue) tag, found in the ingredient list")
            }
        }
    }

    private func apply(_ catalogItem: CatalogProduct) {
        name = catalogItem.name
        brand = catalogItem.brand
        conflictTags = Set(catalogItem.suggestedConflictTags)
        layerCategory = catalogItem.layerCategory
        ingredients = catalogItem.ingredients
    }

    /// Fills in whatever the barcode resolves to, and says plainly when it
    /// resolves to nothing. A miss isn't a failure state -- the form is
    /// right there either way.
    private func lookUp(barcode: String) async {
        isLookingUpBarcode = true
        barcodeMessage = nil
        defer { isLookingUpBarcode = false }

        usedBarcode = true
        guard let match = await BarcodeLookupService.lookup(barcode: barcode) else {
            barcodeMessage = "Couldn't find that barcode. Fill it in below and it'll work the same."
            return
        }

        if let catalogProduct = match.catalogProduct {
            apply(catalogProduct)
        } else {
            name = match.name
            brand = match.brand
            ingredients = match.ingredients
            // Open data has no layering or actives information, so those
            // stay at whatever the user picks rather than being guessed.
            barcodeMessage = "Found \(match.name). Check the step and actives below."
        }
    }

    private func populateFields() {
        if let product {
            name = product.name
            brand = product.brand
            routineTime = product.routineTime
            layerCategory = product.layerCategory
            applicationOrder = product.applicationOrder
            conflictTags = Set(product.conflictTags)
            sizeInML = product.sizeInML
            typicalDoseML = product.typicalDoseML
            openedDate = product.openedDate
            frequency = product.frequency
            monthsAfterOpening = product.monthsAfterOpening ?? 0
            ingredients = product.ingredients
            return
        }
        if let prefillCatalogItem {
            name = prefillCatalogItem.name
            brand = prefillCatalogItem.brand
            conflictTags = Set(prefillCatalogItem.suggestedConflictTags)
            layerCategory = prefillCatalogItem.layerCategory
            typicalDoseML = prefillCatalogItem.layerCategory.defaultDoseML
        }
        if let prefillRoutineTime {
            routineTime = prefillRoutineTime
        }
        if let prefillFrequency {
            frequency = prefillFrequency
        }
    }

    private func save() {
        if var product {
            product.name = name
            product.brand = brand
            product.routineTime = routineTime
            product.layerCategory = layerCategory
            product.applicationOrder = applicationOrder
            product.conflictTags = Array(conflictTags)
            product.sizeInML = sizeInML
            product.typicalDoseML = typicalDoseML
            product.openedDate = openedDate
            product.setFrequency(frequency)
            product.monthsAfterOpening = monthsAfterOpening > 0 ? monthsAfterOpening : nil
            product.ingredients = ingredients
            Task { await appData.updateProduct(product) }
        } else {
            let newProduct = Product(
                userID: appData.userID,
                name: name,
                brand: brand,
                routineTime: routineTime,
                layerCategory: layerCategory,
                applicationOrder: applicationOrder,
                conflictTags: Array(conflictTags),
                sizeInML: sizeInML,
                typicalDoseML: typicalDoseML,
                openedDate: openedDate,
                frequency: frequency,
                monthsAfterOpening: monthsAfterOpening > 0 ? monthsAfterOpening : nil,
                ingredients: ingredients
            )
            Task { await appData.addProduct(newProduct, source: addSource) }
        }
        dismiss()
    }
}
