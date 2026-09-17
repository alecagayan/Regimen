//
//  ContentView.swift
//  Regimen
//

import SwiftUI

struct ContentView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.scenePhase) private var scenePhase

    @State private var navigation = AppNavigation()
    @State private var network = NetworkMonitor.shared
    @State private var notificationRouter = NotificationRouter.shared

    var body: some View {
        @Bindable var appData = appData

        VStack(spacing: 0) {
            SyncStatusBanner(
                isOnline: network.isOnline,
                hasUnsyncedChanges: appData.hasUnsyncedChanges,
                isShowingCachedData: appData.isShowingCachedData,
                isLoading: appData.isLoading
            )

            TabView(selection: $navigation.selectedTab) {
                RoutineView()
                    .tabItem { Label("Routine", systemImage: "checklist") }
                    .tag(AppTab.routine)

                ReorderView()
                    .tabItem { Label("Reorder", systemImage: "cart") }
                    .tag(AppTab.reorder)

                ProgressTabView()
                    .tabItem { Label("Progress", systemImage: "camera.on.rectangle") }
                    .tag(AppTab.progress)

                ProductsView()
                    .tabItem { Label("Cabinet", systemImage: "cross.case.fill") }
                    .tag(AppTab.cabinet)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .motion(Motion.card, value: network.isOnline)
        .motion(Motion.card, value: appData.hasUnsyncedChanges)
        .motion(Motion.card, value: appData.isLoading)
        .tint(Color.brand)
        .toolbarBackground(Color.cardSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(navigation)
        // Reopening the app is when routine check-offs made directly in
        // the widget (see WidgetDataStore) actually get applied -- a user
        // who mostly lives in the widget could otherwise go a long time
        // between cold launches before those ever reach Supabase.
        //
        // `.foreground` rather than the default: this fires on every glance
        // at the app switcher, and a full six-query refetch each time was
        // pure waste. AppData debounces it and still does the cheap work
        // (retry queued writes, re-mint expiring photo URLs) every time.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appData.loadAll(trigger: .foreground) }
        }
        // Widget taps arrive as URLs, notification taps through the
        // delegate -- both end at the same place.
        .onOpenURL { url in
            guard let destination = AppDestination(url: url) else { return }
            navigation.go(to: destination)
        }
        .onChange(of: notificationRouter.pendingDestination) { _, destination in
            guard let destination else { return }
            navigation.go(to: destination)
            notificationRouter.pendingDestination = nil
        }
        .task {
            // Registering the delegate has to happen before any
            // notification can be delivered, and `task` on the root view
            // is the earliest SwiftUI-native hook that runs every launch.
            notificationRouter.start()
        }
        // Writes that fail are reported here rather than swallowed. The
        // check-off path doesn't come through this -- those are queued and
        // retried instead of bothering the user (see PendingWriteQueue).
        .alert(
            "Something Didn't Save",
            isPresented: Binding(
                get: { appData.lastWriteError != nil },
                set: { if !$0 { appData.lastWriteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appData.lastWriteError ?? "")
        }
    }
}
