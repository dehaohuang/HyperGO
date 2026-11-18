import UIKit
import CoreLocation

/// 把导航交给 Google 地图。装了 App 就用 App，没装就用网页版。
enum GoogleMaps {
    /// Google 地图一个导航链接最多支持的目的地数（9 个途经点 + 1 个终点）
    static let maxStopsPerRoute = 10

    static var isAppInstalled: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// 从当前位置导航到单个地点
    static func navigate(to destination: CLLocationCoordinate2D, mode: TravelMode) {
        route(origin: nil, stops: [destination], mode: mode)
    }

    /// 多站路线：按 stops 的顺序依次经过，最后一个是终点。
    /// origin 为 nil 表示从当前位置出发。
    static func route(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D], mode: TravelMode) {
        guard !stops.isEmpty else { return }
        let url = isAppInstalled
            ? appURL(origin: origin, stops: stops, mode: mode)
            : webURL(origin: origin, stops: stops, mode: mode)
        if let url { UIApplication.shared.open(url) }
    }

    private static func string(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }

    /// comgooglemaps://?saddr=&daddr=A+to:B+to:C&directionsmode=driving
    static func appURL(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D], mode: TravelMode) -> URL? {
        let saddr = origin.map(string) ?? ""
        let daddr = stops.map(string).joined(separator: "+to:")
        return URL(string: "comgooglemaps://?saddr=\(saddr)&daddr=\(daddr)&directionsmode=\(mode.rawValue)")
    }

    /// https://www.google.com/maps/dir/?api=1&origin=&destination=&waypoints=a|b&travelmode=
    static func webURL(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D], mode: TravelMode) -> URL? {
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [URLQueryItem(name: "api", value: "1")]
        if let origin { items.append(URLQueryItem(name: "origin", value: string(origin))) }
        items.append(URLQueryItem(name: "destination", value: string(stops.last!)))
        if stops.count > 1 {
            items.append(URLQueryItem(name: "waypoints", value: stops.dropLast().map(string).joined(separator: "|")))
        }
        items.append(URLQueryItem(name: "travelmode", value: mode.rawValue))
        comps.queryItems = items
        return comps.url
    }
}
