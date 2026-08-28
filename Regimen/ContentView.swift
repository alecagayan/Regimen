//
//  ContentView.swift
//  Regimen
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RoutineView()
                .tabItem { Label("Routine", systemImage: "checklist") }

            ReorderView()
                .tabItem { Label("Reorder", systemImage: "cart") }

            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "camera.on.rectangle") }

            ProductsView()
                .tabItem { Label("Products", systemImage: "leaf") }
        }
        .tint(Color.brand)
        .toolbarBackground(Color.cardSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
