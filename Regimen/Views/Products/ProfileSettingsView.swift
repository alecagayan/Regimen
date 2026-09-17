//
//  ProfileSettingsView.swift
//  Regimen
//

import StoreKit
import SwiftUI
import Supabase
import os

/// The pane behind the profile icon: account info (name, editable; email
/// and member-since, read-only from the Supabase session), a couple of
/// device-local settings, and sign out.
struct ProfileSettingsView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.signOut) private var signOut

    @State private var auth = AuthService.shared
    @State private var name = ""
    @State private var isSavingName = false
    @State private var notificationsEnabled = NotificationManager.shared.remindersEnabled
    @State private var routineRemindersEnabled = NotificationManager.shared.routineRemindersEnabled
    @State private var amReminderHour = NotificationManager.shared.amReminderHour
    @State private var pmReminderHour = NotificationManager.shared.pmReminderHour
    @State private var changeoverHour = RoutineClock.changeoverHour
    @State private var showingSignOutConfirmation = false
    @State private var showingPaywall = false
    @State private var showingSkinQuiz = false
    @State private var exportURL: URL?
    @State private var analyticsEnabled = Analytics.isEnabled
    @State private var showingManageSubscriptions = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?

    private var email: String { auth.session?.user.email ?? "" }

    private var memberSince: String? {
        guard let createdAt = auth.session?.user.createdAt else { return nil }
        return createdAt.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    profileHeader

                    VStack(spacing: Theme.Spacing.sm) {
                        AuthField(title: "Name", text: $name, textContentType: .name)
                        Button(action: saveName) {
                            if isSavingName {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save Name")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingName)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    premiumSection

                    settingsSection

                    Button {
                        showingSignOutConfirmation = true
                    } label: {
                        Text("Sign Out")
                            .font(.rowTitle)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            showingDeleteAccountConfirmation = true
                        } label: {
                            if isDeletingAccount {
                                ProgressView().tint(.red)
                            } else {
                                Text("Delete Account")
                            }
                        }
                        .font(.rowSubtitle.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.8))
                        .disabled(isDeletingAccount)

                        if let deleteAccountErrorMessage {
                            Text(deleteAccountErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    // Reachable from inside the app, not only from the
                    // App Store listing -- an account holder has to be
                    // able to find the terms they agreed to and the policy
                    // covering the photos they've stored.
                    HStack(spacing: Theme.Spacing.xs) {
                        Link("Terms of Use", destination: LegalLinks.termsOfUse)
                        Text("·").foregroundStyle(.secondary)
                        Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                    }
                    .font(.caption.weight(.semibold))
                    .tint(Color.brand)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Regimen \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadProfile() }
            .confirmationDialog("Sign Out?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await signOut()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive, action: deleteAccount)
            } message: {
                Text("This permanently deletes your account, products, photos, and history. This can't be undone.")
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $showingSkinQuiz) {
                // No completion handler: opened from Settings the quiz is
                // just an editor, with nothing to present afterward.
                RoutineQuizView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        }
    }

    private var premiumSection: some View {
        Group {
            if appData.isPremium {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium")
                            .font(.rowTitle)
                        Text("You have access to every feature.")
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Manage") {
                        showingManageSubscriptions = true
                    }
                    .font(.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.secondary)
                    #if DEBUG
                    // StoreKit Testing has its own way to cancel a
                    // subscription (Debug > StoreKit > Manage Transactions
                    // in Xcode/Simulator), but that can take a moment to
                    // reflect -- this is a faster manual escape hatch for
                    // testing the free-tier paywall gates during development.
                    Button("Force Downgrade") {
                        Task { await appData.setPremium(false) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    #endif
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
                .padding(.horizontal, Theme.Spacing.lg)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Go Premium")
                                .font(.rowTitle)
                            Text("Unlock skin scans, trends, and more.")
                                .font(.rowSubtitle)
                                .opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(Theme.Spacing.md)
                    .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ProductAvatar(name: name.isEmpty ? email : name, size: 72)
            VStack(spacing: 2) {
                if !email.isEmpty {
                    Text(email)
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                if let memberSince {
                    Text("Member since \(memberSince)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("SETTINGS")
                .font(.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.lg)

            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reorder Reminders")
                        .font(.rowTitle)
                    Text("A week before a product is predicted to run out.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.brand)
            .padding(Theme.Spacing.md)
            .cardStyle()
            .padding(.horizontal, Theme.Spacing.lg)
            .onChange(of: notificationsEnabled, onNotificationsToggleChanged)

            Toggle(isOn: $routineRemindersEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Routine Reminders")
                        .font(.rowTitle)
                    Text("A daily nudge at your AM and PM times.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.brand)
            .padding(Theme.Spacing.md)
            .cardStyle()
            .padding(.horizontal, Theme.Spacing.lg)
            .onChange(of: routineRemindersEnabled) { _, enabled in
                NotificationManager.shared.routineRemindersEnabled = enabled
                NotificationManager.shared.refreshRoutineReminders()
                if enabled {
                    Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
                }
            }

            if routineRemindersEnabled {
                VStack(spacing: Theme.Spacing.sm) {
                    hourPicker(title: "Morning at", selection: $amReminderHour)
                    Divider()
                    hourPicker(title: "Evening at", selection: $pmReminderHour)
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
                .padding(.horizontal, Theme.Spacing.lg)
                .onChange(of: amReminderHour) { _, hour in
                    NotificationManager.shared.amReminderHour = hour
                    NotificationManager.shared.refreshRoutineReminders()
                }
                .onChange(of: pmReminderHour) { _, hour in
                    NotificationManager.shared.pmReminderHour = hour
                    NotificationManager.shared.refreshRoutineReminders()
                }
            }

            // Night shifts exist. A hardcoded midday boundary showed anyone
            // working them the wrong half of their routine for their whole
            // waking shift, in both the app and the widget.
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day Starts At")
                        .font(.rowTitle)
                    Text("When your routine switches from AM to PM. The widget follows this too.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                Picker("Day starts at", selection: $changeoverHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(RoutineClock.label(forHour: hour)).tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
                .clipped()
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
            .padding(.horizontal, Theme.Spacing.lg)
            .onChange(of: changeoverHour) { _, hour in
                RoutineClock.changeoverHour = hour
            }

            Toggle(isOn: $analyticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Usage Data")
                        .font(.rowTitle)
                    Text("Anonymous counts of which features get used, stored with your account. Never your photos or scores.")
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.brand)
            .padding(Theme.Spacing.md)
            .cardStyle()
            .padding(.horizontal, Theme.Spacing.lg)
            .onChange(of: analyticsEnabled) { _, enabled in
                Analytics.isEnabled = enabled
            }

            Button {
                exportURL = DataExportService.write(appData.exportSnapshot())
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Your Data")
                            .font(.rowTitle)
                            .foregroundStyle(.primary)
                        Text("A JSON file of your products, history, and scans.")
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "square.and.arrow.up")
                        .font(.rowTitle)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)

            // The quiz used to be reachable only by starting a routine
            // build, so a mis-tapped answer was baked in permanently even
            // though it shapes every recommendation the app makes.
            Button {
                showingSkinQuiz = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Skin Profile")
                            .font(.rowTitle)
                            .foregroundStyle(.primary)
                        Text(skinProfileSummary)
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(Theme.Spacing.md)
                .cardStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    private func hourPicker(title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(RoutineClock.label(forHour: hour)).tag(hour)
            }
        }
        .font(.rowTitle)
    }

    /// Reads back the saved answers so the row shows what's actually in
    /// effect, rather than making the user open the quiz to find out.
    private var skinProfileSummary: String {
        guard appData.hasSkinProfile else {
            return "Not set. Answers tune what the app recommends."
        }
        let profile = appData.effectiveSkinProfile
        let sensitivity = profile.isSensitive ? "sensitive" : "not sensitive"
        return "\(profile.skinType.rawValue), \(sensitivity), \(profile.experience.rawValue.lowercased())"
    }

    private func loadProfile() async {
        guard let userID = auth.currentUserID else { return }
        if let profile = try? await ProfileService.fetch(userID: userID) {
            name = profile.name
        }
    }

    private func saveName() {
        guard let userID = auth.currentUserID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSavingName = true
        Task {
            defer { isSavingName = false }
            try? await ProfileService.updateName(userID: userID, name: trimmed)
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        Task {
            defer { isDeletingAccount = false }
            do {
                try await AuthService.shared.deleteAccount()
                dismiss()
            } catch {
                AppLog.auth.error("deleteAccount failed: \(error.localizedDescription, privacy: .public)")
                deleteAccountErrorMessage = "Couldn't delete your account. Please try again."
            }
        }
    }

    private func onNotificationsToggleChanged(_ oldValue: Bool, _ newValue: Bool) {
        NotificationManager.shared.remindersEnabled = newValue
        guard newValue else { return }
        // Turning reminders back on doesn't retroactively know about every
        // product's current prediction, so recompute and reschedule all of
        // them immediately rather than waiting for the next edit/check-off.
        for product in appData.products where !product.isArchived {
            NotificationManager.shared.refreshNotification(for: product, usageLogs: appData.usageLogs(for: product))
        }
    }
}
