import SwiftUI
import SwiftData

@main
struct HyperGOApp: App {
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
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            PlaceListView()
                .tabItem { Label("地点", systemImage: "star.square.on.square") }
            PlacesMapView()
                .tabItem { Label("地图", systemImage: "map") }
            RoutePlannerView()
                .tabItem { Label("路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
        }
        .onAppear {
            locationManager.start()
            #if DEBUG
            SampleData.insertIfRequested(into: context)
            #endif
        }
    }
}

#if DEBUG
/// 仅调试用：启动参数带 -seedSamples 且没有地点时，放入几个多伦多示例地点，方便在模拟器里预览
enum SampleData {
    static func insertIfRequested(into context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSamples") else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Place>())) ?? 0
        guard count == 0 else { return }
        let samples: [(String, String, String, Double, Double)] = [
            ("家", "house.fill", "#34C759", 43.6629, -79.3957),
            ("公司", "briefcase.fill", "#007AFF", 43.6481, -79.3816),
            ("超市", "cart.fill", "#FF9500", 43.6544, -79.3807),
            ("咖啡", "☕️", "#A2845E", 43.6505, -79.3871),
            ("健身房", "dumbbell.fill", "#FF2D55", 43.6677, -79.3948),
            ("加油站", "fuelpump.fill", "#FFCC00", 43.6590, -79.4010),
            ("机场", "airplane", "#5856D6", 43.6777, -79.6248),
        ]
        for (i, s) in samples.enumerated() {
            context.insert(Place(name: s.0, icon: s.1, colorHex: s.2, latitude: s.3, longitude: s.4, sortIndex: i))
        }
    }
}
#endif
