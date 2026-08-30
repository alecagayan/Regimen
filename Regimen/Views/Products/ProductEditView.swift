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

    private var isEditing: Bool { product != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Button {
                            showingCatalogPicker = true
                        } label: {
                            Label("Choose from Catalog", systemImage: "magnifyingglass")
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
                    Stepper("Order within step: \(applicationOrder)", value: $applicationOrder, in: 1...20)
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Step decides the overall order (cleanser, then treatments, then moisturizer, and so on). \"Order within step\" only breaks ties between two products in the same step.")
                }
                Section {
                    conflictTagGrid
                } header: {
                    Text("Active Ingredients")
                } footer: {
                    Text("Select every one that applies — many products combine more than one. This is what the Routine tab checks for known conflicts, like a retinoid and an exfoliating acid on the same night.")
                }
                Section {
                    HStack {
                        Text("Size")
                        Spacer()
                        TextField("mL", value: $sizeInML, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mL").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Amount per use")
                        Spacer()
                        TextField("mL", value: $typicalDoseML, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mL").foregroundStyle(.secondary)
                    }
                    DatePicker("Opened", selection: $openedDate, displayedComponents: .date)
                } header: {
                    Text("Bottle")
                } footer: {
                    Text("Amount per use is what each check-off in Routine counts toward depletion. Defaults by step, but skincare isn't measured out precisely — adjust it if a product runs out faster or slower than predicted.")
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
                    name = catalogItem.name
                    brand = catalogItem.brand
                    conflictTags = Set(catalogItem.suggestedConflictTags)
                    layerCategory = catalogItem.layerCategory
                }
            }
        }
    }

    /// A wrapping grid of toggleable chips rather than a single picker --
    /// a real product often carries more than one flaggable active (a
    /// serum combining a retinoid with niacinamide, say), which a picker's
    /// one-of-many selection couldn't represent.
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
                openedDate: openedDate
            )
            Task { await appData.addProduct(newProduct) }
        }
        dismiss()
    }
}
