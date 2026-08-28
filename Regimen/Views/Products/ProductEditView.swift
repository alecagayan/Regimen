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

    @State private var name = ""
    @State private var brand = ""
    @State private var routineTime: RoutineTime = .am
    @State private var layerCategory: LayerCategory = .treatment
    @State private var applicationOrder = 1
    @State private var conflictTag: ConflictTag = .none
    @State private var sizeInML: Double = 30
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
                    Stepper("Order within step: \(applicationOrder)", value: $applicationOrder, in: 1...20)
                    Picker("Conflict Tag", selection: $conflictTag) {
                        ForEach(ConflictTag.allCases) { tag in
                            Text(tag.rawValue).tag(tag)
                        }
                    }
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Step decides the overall order (cleanser, then treatments, then moisturizer, and so on). \"Order within step\" only breaks ties between two products in the same step.")
                }
                Section("Bottle") {
                    HStack {
                        Text("Size")
                        Spacer()
                        TextField("mL", value: $sizeInML, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mL").foregroundStyle(.secondary)
                    }
                    DatePicker("Opened", selection: $openedDate, displayedComponents: .date)
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
            .onAppear(perform: populateFieldsIfEditing)
            .sheet(isPresented: $showingCatalogPicker) {
                CatalogPickerView { catalogItem in
                    name = catalogItem.name
                    brand = catalogItem.brand
                    conflictTag = catalogItem.suggestedConflictTag
                    layerCategory = catalogItem.layerCategory
                }
            }
        }
    }

    private func populateFieldsIfEditing() {
        guard let product else { return }
        name = product.name
        brand = product.brand
        routineTime = product.routineTime
        layerCategory = product.layerCategory
        applicationOrder = product.applicationOrder
        conflictTag = product.conflictTag
        sizeInML = product.sizeInML
        openedDate = product.openedDate
    }

    private func save() {
        if var product {
            product.name = name
            product.brand = brand
            product.routineTime = routineTime
            product.layerCategory = layerCategory
            product.applicationOrder = applicationOrder
            product.conflictTag = conflictTag
            product.sizeInML = sizeInML
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
                conflictTag: conflictTag,
                sizeInML: sizeInML,
                openedDate: openedDate
            )
            Task { await appData.addProduct(newProduct) }
        }
        dismiss()
    }
}
