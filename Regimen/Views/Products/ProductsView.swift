//
//  ProductsView.swift
//  Regimen
//

import SwiftUI

struct ProductsView: View {
    @Environment(AppData.self) private var appData
    @Environment(AppNavigation.self) private var navigation

    @State private var showingAddSheet = false
    @State private var editingProduct: Product?
    @State private var detailProduct: Product?
    @State private var showingEmpties = false
    @State private var showArchived = false
    @State private var showingProfile = false
    /// Held while the confirmation is up. `role: .destructive` on a Menu
    /// button only colours it red -- it doesn't prompt -- so deleting a
    /// product used to be a single mis-tap that also cascaded away every
    /// usage log attached to it (see `on delete cascade` in schema.sql).
    @State private var productPendingDeletion: Product?
    @State private var searchText = ""
    @State private var sortOrder: CabinetSort = .name

    private var visibleProducts: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appData.products
            .filter { showArchived || !$0.isArchived }
            .filter { product in
                guard !query.isEmpty else { return true }
                return product.name.lowercased().contains(query)
                    || product.brand.lowercased().contains(query)
            }
            .sorted(by: sortOrder.comparator)
    }

    private var subtitle: String? {
        guard !appData.products.isEmpty else { return nil }
        let active = appData.products.filter { !$0.isArchived }.count
        let archived = appData.products.count - active
        return archived > 0 ? "\(active) active · \(archived) archived" : "\(active) product\(active == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    ScreenHeader(title: "Cabinet", subtitle: subtitle) {
                        Button {
                            showingProfile = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Profile and settings")
                    }

                    // Only once there's enough in the cabinet for finding
                    // something to be a real problem -- a search field above
                    // three products is just clutter.
                    if appData.products.count >= 6 {
                        cabinetControls
                    }

                    if visibleProducts.isEmpty {
                        EmptyStateView(
                            icon: "cross.case",
                            title: showArchived ? "Nothing Here Yet" : "Cabinet's Empty",
                            message: "Add the products you use and Regimen will build your routine, track what's running low, and watch your progress.",
                            actionTitle: "Add Your First Product",
                            action: { showingAddSheet = true }
                        )
                        .padding(.top, Theme.Spacing.xl)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(visibleProducts) { product in
                                    ProductRow(
                                        product: product,
                                        onOpen: { detailProduct = product },
                                        onEdit: { editingProduct = product },
                                        onArchiveToggle: { Task { await toggleArchive(product) } },
                                        onDelete: { productPendingDeletion = product }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.floatingButtonClearance)
                        }
                        .refreshable { await appData.loadAll() }
                    }
                }
                .background(Color.appBackground.ignoresSafeArea())

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.brand.gradient, in: Circle())
                        .shadow(color: Color.brand.opacity(0.35), radius: 14, x: 0, y: 8)
                }
                .accessibilityLabel("Add a product")
                .padding(.trailing, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
            .toolbar(.hidden, for: .navigationBar)
            // Another tab handed the user here to add a product (see
            // AppNavigation) -- consume the one-shot signal and present.
            .onChange(of: navigation.isAddingProduct) { _, isAdding in
                guard isAdding else { return }
                showingAddSheet = true
                navigation.isAddingProduct = false
            }
            .sheet(isPresented: $showingAddSheet) {
                ProductEditView(product: nil)
            }
            .sheet(item: $detailProduct) { product in
                ProductDetailView(product: product)
            }
            .sheet(item: $editingProduct) { product in
                ProductEditView(product: product)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileSettingsView()
            }
            .sheet(isPresented: $showingEmpties) {
                EmptiesView()
            }
            .confirmationDialog(
                productPendingDeletion.map { "Delete \($0.name)?" } ?? "Delete this product?",
                isPresented: Binding(
                    get: { productPendingDeletion != nil },
                    set: { if !$0 { productPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: productPendingDeletion
            ) { product in
                Button("Delete", role: .destructive) {
                    Task { await appData.deleteProduct(product) }
                    productPendingDeletion = nil
                }
                Button("Archive Instead") {
                    Task { await toggleArchive(product) }
                    productPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { productPendingDeletion = nil }
            } message: { _ in
                Text("This also deletes its usage history, which your streak is built from. Archiving keeps the history and hides the product.")
            }
        }
    }

    /// Search, sort and the archived filter. The archived toggle used to
    /// float next to the add button, where a filter reads as a second
    /// primary action rather than a view option.
    private var cabinetControls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                TextField("Search cabinet", text: $searchText)
                    .font(.rowSubtitle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.cardSurface))
            .overlay(Capsule().strokeBorder(Color.subtleBorder, lineWidth: 1))

            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(CabinetSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Toggle("Show Archived", isOn: $showArchived)
                Divider()
                Button("Empties", systemImage: "archivebox") { showingEmpties = true }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(showArchived || sortOrder != .name ? Color.brand : .secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Sort and filter")
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func toggleArchive(_ product: Product) async {
        var updated = product
        updated.isArchived.toggle()
        await appData.updateProduct(updated)
    }
}

/// How the cabinet is ordered. Defaults to name because that's what
/// someone scanning for a specific bottle is looking for; the other two
/// answer "what am I actually using" and "what did I just buy".
enum CabinetSort: String, CaseIterable, Identifiable {
    case name
    case step
    case recentlyOpened

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Name"
        case .step: "Routine Step"
        case .recentlyOpened: "Recently Opened"
        }
    }

    var comparator: (Product, Product) -> Bool {
        switch self {
        case .name:
            return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .step:
            return { lhs, rhs in
                lhs.layerCategory.rank == rhs.layerCategory.rank
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.layerCategory.rank < rhs.layerCategory.rank
            }
        case .recentlyOpened:
            return { $0.openedDate > $1.openedDate }
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onArchiveToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductAvatar(name: product.name, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(product.brand) · \(product.routineTime.rawValue) · \(Int(product.sizeInML)) mL")
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if product.isArchived {
                    StatusChip(text: "Archived", tint: .secondary)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button(
                    product.isArchived ? "Unarchive" : "Archive",
                    systemImage: product.isArchived ? "tray.and.arrow.up" : "archivebox",
                    action: onArchiveToggle
                )
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .opacity(product.isArchived ? 0.6 : 1)
        .contentShape(Rectangle())
        // Opens the product, not the edit form -- a form was an odd primary
        // action for a row whose usage history the app already tracks.
        .onTapGesture(perform: onOpen)
    }
}
