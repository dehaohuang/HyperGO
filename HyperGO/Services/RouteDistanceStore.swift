import CoreLocation
import MapKit
import Observation

/// 计算并缓存「当前位置 → 各地点」的最短实际道路距离
/// - 用 MapKit 路线规划，请求备选路线后取最短的一条
/// - 位置移动超过 `refreshThreshold` 米或出行方式改变时清空重算
@MainActor
@Observable
final class RouteDistanceStore {
    private(set) var meters: [String: CLLocationDistance] = [:]

    @ObservationIgnored private var origin: CLLocation?
    @ObservationIgnored private var mode: TravelMode?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let refreshThreshold: CLLocationDistance = 200

    static func key(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", c.latitude, c.longitude)
    }

    /// 已算出的道路距离；还没算好或失败时为 nil
    func distance(to c: CLLocationCoordinate2D) -> CLLocationDistance? {
        meters[Self.key(c)]
    }

    func refresh(from location: CLLocation?, to destinations: [CLLocationCoordinate2D], mode: TravelMode) {
        guard let location else { return }
        let moved = origin.map { $0.distance(from: location) > refreshThreshold } ?? true
        if moved || mode != self.mode {
            meters = [:]
            origin = location
            self.mode = mode
        }
        guard let origin else { return }

        var seen = Set<String>()
        let missing = destinations.filter { meters[Self.key($0)] == nil && seen.insert(Self.key($0)).inserted }
        guard !missing.isEmpty else { return }

        task?.cancel()
        task = Task { [weak self] in
            // 逐个请求，避免触发 MapKit 的频率限制
            for c in missing {
                if Task.isCancelled { return }
                guard let d = await Self.shortestRoute(from: origin.coordinate, to: c, mode: mode) else { continue }
                if Task.isCancelled { return }
                self?.meters[Self.key(c)] = d
            }
        }
    }

    private static func shortestRoute(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                                      mode: TravelMode) async -> CLLocationDistance? {
        let type = mode.mkTransportType

        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        req.transportType = type
        req.requestsAlternateRoutes = true
        guard let routes = try? await MKDirections(request: req).calculate().routes else { return nil }
        return routes.map(\.distance).min()
    }
}
