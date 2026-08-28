//
//  ProductsView.swift
//  Regimen
//

import SwiftUI

struct ProductsView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.signOut) private var signOut

    @State private var showingAddSheet = false
    @State private var editingProduct: Product?
    @State private var showArchived = false
    @State private var showingSignOutConfirmation = false

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
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        HStack(alignment: .top) {
                            ScreenHeader(title: "Products", subtitle: subtitle)
                            Spacer()
                            Button {
                                showingSignOutConfirmation = true
                            } label: {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, Theme.Spacing.md)
                            .padding(.trailing, Theme.Spacing.lg)
                        }

                        HStack {
                            Spacer()
                            Button {
                                showArchived.toggle()
                            } label: {
                                Label("Archived", systemImage: showArchived ? "archivebox.fill" : "archivebox")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(showArchived ? Color.brand : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(showArchived ? Color.brand.opacity(0.12) : Color.cardSurface)
                            )
                            .overlay(Capsule().strokeBorder(Color.subtleBorder, lineWidth: 1))
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

                        if visibleProducts.isEmpty {
                            EmptyStateView(
                                icon: "leaf",
                                title: "No Products",
                                message: "Tap + to add your first product."
                            )
                            .padding(.top, Theme.Spacing.xl)
                        } else {
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
                        }
                    }
                    .padding(.bottom, 110)
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
                .padding(.trailing, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddSheet) {
                ProductEditView(product: nil)
            }
            .sheet(item: $editingProduct) { product in
                ProductEditView(product: product)
            }
            .confirmationDialog("Sign Out?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { try? await signOut() }
                }
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
                    .font(.emphasized(16))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(product.brand) · \(product.routineTime.rawValue) · \(Int(product.sizeInML)) mL")
                    .font(.system(size: 12.5))
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
                    .font(.system(size: 15, weight: .semibold))
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
