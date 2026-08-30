//
//  ContentView.swift
//  Regimen
//

import SwiftUI

struct ContentView: View {
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
    }
}
