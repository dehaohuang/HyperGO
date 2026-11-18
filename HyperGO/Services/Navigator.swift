import UIKit
import CoreLocation

/// 用来导航的地图 App（在设置里选择）
enum NavApp: String, CaseIterable, Identifiable {
    case google, apple, waze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google 地图"
        case .apple: "Apple 地图"
        case .waze: "Waze"
        }
    }

    /// 一次导航最多能经过几个目的地。Google 地图 9 个途经点 + 1 个终点；Apple 地图和 Waze 只能一个目的地
    var maxStopsPerRoute: Int {
        switch self {
        case .google: 10
        case .apple, .waze: 1
        }
    }

    private var scheme: String {
        switch self {
        case .google: "comgooglemaps://"
        case .apple: "maps://"
        case .waze: "waze://"
        }
    }

    var isInstalled: Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// 设置里可选的：已安装的 App；Google 地图没装也列出（用网页版）
    static var choices: [NavApp] {
        allCases.filter { $0 == .google || $0.isInstalled }
    }

    /// 当前使用的导航 App（选过的 App 被删掉了就退回 Google 地图）
    static var current: NavApp {
        let saved = NavApp(rawValue: UserDefaults.standard.string(forKey: "navApp") ?? "") ?? .google
        return saved.isInstalled || saved == .google ? saved : .google
    }

    /// 设置和按钮上显示的名字
    var displayName: String {
        self == .google && !isInstalled ? "Google 地图（网页版）" : title
    }
}

/// 把导航交给选定的地图 App
enum Navigator {
    /// 从当前位置导航到单个地点
    static func navigate(to destination: CLLocationCoordinate2D) {
        route(origin: nil, stops: [destination])
    }

    /// 多站路线：按 stops 的顺序依次经过，最后一个是终点。origin 为 nil 表示从当前位置出发。
    /// 只支持一个目的地的 App 只用第一站。
    static func route(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D], app: NavApp = .current) {
        guard !stops.isEmpty else { return }
        let url: URL?
        switch app {
        case .google:
            url = app.isInstalled ? googleAppURL(origin: origin, stops: stops) : googleWebURL(origin: origin, stops: stops)
        case .apple:
            url = appleURL(origin: origin, destination: stops[0])
        case .waze:
            url = URL(string: "waze://?ll=\(string(stops[0]))&navigate=yes")
        }
        if let url { UIApplication.shared.open(url) }
    }

    private static func string(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }

    /// comgooglemaps://?saddr=&daddr=A+to:B+to:C&directionsmode=driving
    static func googleAppURL(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D]) -> URL? {
        let saddr = origin.map(string) ?? ""
        let daddr = stops.map(string).joined(separator: "+to:")
        return URL(string: "comgooglemaps://?saddr=\(saddr)&daddr=\(daddr)&directionsmode=driving")
    }

    /// https://www.google.com/maps/dir/?api=1&origin=&destination=&waypoints=a|b&travelmode=driving
    static func googleWebURL(origin: CLLocationCoordinate2D?, stops: [CLLocationCoordinate2D]) -> URL? {
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [URLQueryItem(name: "api", value: "1")]
        if let origin { items.append(URLQueryItem(name: "origin", value: string(origin))) }
        items.append(URLQueryItem(name: "destination", value: string(stops.last!)))
        if stops.count > 1 {
            items.append(URLQueryItem(name: "waypoints", value: stops.dropLast().map(string).joined(separator: "|")))
        }
        items.append(URLQueryItem(name: "travelmode", value: "driving"))
        comps.queryItems = items
        return comps.url
    }

    /// maps://?saddr=&daddr=lat,lon&dirflg=d（驾车）
    static func appleURL(origin: CLLocationCoordinate2D?, destination: CLLocationCoordinate2D) -> URL? {
        var s = "maps://?daddr=\(string(destination))&dirflg=d"
        if let origin { s += "&saddr=\(string(origin))" }
        return URL(string: s)
    }
}
