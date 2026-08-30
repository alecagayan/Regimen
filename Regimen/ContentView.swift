//
//  ContentView.swift
//  Regimen
//

import SwiftUI

struct ContentView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.scenePhase) private var scenePhase

    @State private var navigation = AppNavigation()

    var body: some View {
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
        .tint(Color.brand)
        .toolbarBackground(Color.cardSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(navigation)
        // Reopening the app is when routine check-offs made directly in
        // the widget (see WidgetDataStore) actually get applied -- a user
        // who mostly lives in the widget could otherwise go a long time
        // between cold launches before those ever reach Supabase.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appData.loadAll() }
        }
    }
}
