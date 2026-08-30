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
    @State private var showArchived = false
    @State private var showingProfile = false

    private var visibleProducts: [Product] {
        appData.products.filter { showArchived || !$0.isArchived }
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
                                        onEdit: { editingProduct = product },
                                        onArchiveToggle: { Task { await toggleArchive(product) } },
                                        onDelete: { Task { await appData.deleteProduct(product) } }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.floatingButtonClearance)
                        }
                    }
                }
                .background(Color.appBackground.ignoresSafeArea())

                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    Button {
                        showArchived.toggle()
                    } label: {
                        Label("Archived", systemImage: showArchived ? "archivebox.fill" : "archivebox")
                            .font(.rowSubtitle.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showArchived ? Color.brand : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(showArchived ? Color.brand.opacity(0.12) : Color.cardSurface)
                    )
                    .overlay(Capsule().strokeBorder(Color.subtleBorder, lineWidth: 1))

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
                }
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
            .sheet(item: $editingProduct) { product in
                ProductEditView(product: product)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileSettingsView()
            }
        }
    }

    private func toggleArchive(_ product: Product) async {
        var updated = product
        updated.isArchived.toggle()
        await appData.updateProduct(updated)
    }
}

private struct ProductRow: View {
    let product: Product
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
        .onTapGesture(perform: onEdit)
    }
}
