import SwiftUI
import SwiftData

@main
struct QuickNavApp: App {
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
        }
        .modelContainer(for: Place.self)
    }
}

struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager

    var body: some View {
        TabView {
            PlaceListView()
                .tabItem { Label("地点", systemImage: "star.square.on.square") }
            PlacesMapView()
                .tabItem { Label("地图", systemImage: "map") }
            RoutePlannerView()
                .tabItem { Label("路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
        }
        .onAppear { locationManager.start() }
    }
}
