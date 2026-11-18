import Foundation
import CoreLocation
import MapKit
import Observation

/// 油品
enum FuelType: String, CaseIterable, Identifiable {
    case regular, midgrade, premium, diesel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "普通 87"
        case .midgrade: "中级 89"
        case .premium: "高级 91+"
        case .diesel: "柴油"
        }
    }

    /// Google 地点接口里的名称
    var googleNames: [String] {
        switch self {
        case .regular: ["REGULAR_UNLEADED"]
        case .midgrade: ["MIDGRADE"]
        case .premium: ["PREMIUM", "SP95", "SP98", "SP99", "SP100"]
        case .diesel: ["DIESEL", "DIESEL_PLUS"]
        }
    }
}

struct FuelPrice {
    /// 每升价格（元）
    let perLitre: Double
    let currency: String
    let updated: Date?
}

struct GasStation: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    /// 各油品价格（只有用 Google 密钥时才有）
    var prices: [FuelType: FuelPrice] = [:]
}

/// 查找附近加油站：
/// - 填了 Google 密钥：用 Google 地点接口（带实时油价），结果缓存，避免多次计费
/// - 没填：用 Apple 地图找加油站（免费，没有油价）
@MainActor
@Observable
final class GasStationService {
    static let shared = GasStationService()

    private(set) var stations: [GasStation] = []
    private(set) var loading = false
    private(set) var hasPrices = false
    private(set) var lastUpdated: Date?
    var errorMessage: String?

    @ObservationIgnored private var lastCenter: CLLocation?
    @ObservationIgnored private var lastRadius: Double = 0
    @ObservationIgnored private var lastUsedKey = ""

    static let keyDefaultsKey = "googlePlacesKey"

    static var apiKey: String {
        (UserDefaults.standard.string(forKey: keyDefaultsKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 本月 Google 查询次数（每月前 1000 次免费）
    static var monthlyGoogleCalls: Int {
        let d = UserDefaults.standard
        return d.string(forKey: "places.month") == monthKey ? d.integer(forKey: "places.count") : 0
    }

    private static var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private static func countGoogleCall() {
        let d = UserDefaults.standard
        let n = monthlyGoogleCalls + 1
        d.set(monthKey, forKey: "places.month")
        d.set(n, forKey: "places.count")
    }

    /// 位置变化不大、时间不久时直接用缓存；force = 用户手动刷新
    func refresh(near location: CLLocation?, radius: Double, force: Bool = false) async {
        guard let location, !loading else { return }
        let key = Self.apiKey
        if !force, let last = lastCenter, let time = lastUpdated,
           last.distance(from: location) < 1500,
           Date.now.timeIntervalSince(time) < 20 * 60,
           radius == lastRadius, key == lastUsedKey {
            return
        }
        loading = true
        defer { loading = false }
        errorMessage = nil

        var result: [GasStation]?
        var priced = false
        if !key.isEmpty {
            do {
                result = try await Self.googleSearch(center: location.coordinate, radius: radius, key: key)
                priced = true
            } catch {
                errorMessage = "Google 油价查询失败：\(error.localizedDescription)。先显示 Apple 地图的加油站（没有油价）。"
            }
        }
        if result == nil {
            result = await Self.appleSearch(center: location.coordinate, radius: radius)
        }
        stations = result ?? []
        #if DEBUG
        // 仅调试：启动参数带 -mockFuelPrices 时给加油站编一些油价，检查界面用
        if ProcessInfo.processInfo.arguments.contains("-mockFuelPrices") {
            for i in stations.indices {
                let base = 1.39 + Double((stations[i].id.hashValue & 0xFF) % 20) / 100
                stations[i].prices = [.regular: FuelPrice(perLitre: base, currency: "CAD", updated: .now.addingTimeInterval(-3600)),
                                      .premium: FuelPrice(perLitre: base + 0.2, currency: "CAD", updated: .now.addingTimeInterval(-7200))]
            }
            priced = true
        }
        #endif
        hasPrices = priced && stations.contains { !$0.prices.isEmpty }
        lastCenter = location
        lastRadius = radius
        lastUsedKey = key
        lastUpdated = .now
    }

    // MARK: - Apple 地图

    private static func appleSearch(center: CLLocationCoordinate2D, radius: Double) async -> [GasStation] {
        let req = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        guard let items = try? await MKLocalSearch(request: req).start().mapItems else { return [] }
        // 有时会混进名字像加油站的其他地方（比如消防站），只留真正的加油站
        return items.filter { $0.pointOfInterestCategory == .gasStation }.map { item in
            let c = item.placemark.coordinate
            let p = item.placemark
            let address = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
            return GasStation(id: String(format: "apple-%.5f,%.5f", c.latitude, c.longitude),
                              name: item.name ?? "加油站", address: address, coordinate: c)
        }
    }

    // MARK: - Google 地点接口（新版 Places API）

    private struct GoogleResponse: Decodable {
        struct Place: Decodable {
            struct Name: Decodable { let text: String? }
            struct Location: Decodable { let latitude: Double; let longitude: Double }
            struct FuelOptions: Decodable { let fuelPrices: [Price]? }
            struct Price: Decodable {
                struct Money: Decodable { let currencyCode: String?; let units: String?; let nanos: Int? }
                let type: String?
                let price: Money?
                let updateTime: String?
            }
            let id: String
            let displayName: Name?
            let formattedAddress: String?
            let shortFormattedAddress: String?
            let location: Location?
            let fuelOptions: FuelOptions?
        }
        let places: [Place]?
    }

    private struct GoogleError: Decodable {
        struct Body: Decodable { let message: String? }
        let error: Body?
    }

    private static func googleSearch(center: CLLocationCoordinate2D, radius: Double, key: String) async throws -> [GasStation] {
        var req = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        // 密钥限制为「iOS 应用」时需要带上 Bundle ID
        req.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.setValue("places.id,places.displayName,places.formattedAddress,places.shortFormattedAddress,places.location,places.fuelOptions",
                     forHTTPHeaderField: "X-Goog-FieldMask")
        let body: [String: Any] = [
            "includedTypes": ["gas_station"],
            "maxResultCount": 20,
            "rankPreference": "DISTANCE",
            "locationRestriction": ["circle": [
                "center": ["latitude": center.latitude, "longitude": center.longitude],
                "radius": min(radius, 50_000),
            ]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        countGoogleCall()
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(GoogleError.self, from: data))?.error?.message ?? "错误代码 \(http.statusCode)"
            throw NSError(domain: "GooglePlaces", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        return (decoded.places ?? []).compactMap { p in
            guard let loc = p.location else { return nil }
            var station = GasStation(id: p.id, name: p.displayName?.text ?? "加油站",
                                     address: p.shortFormattedAddress ?? p.formattedAddress ?? "",
                                     coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude))
            for fp in p.fuelOptions?.fuelPrices ?? [] {
                guard let type = fp.type, let money = fp.price,
                      let fuel = FuelType.allCases.first(where: { $0.googleNames.contains(type) }) else { continue }
                let value = (Double(money.units ?? "0") ?? 0) + Double(money.nanos ?? 0) / 1_000_000_000
                guard value > 0 else { continue }
                let date = fp.updateTime.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
                // 同一类有多种（如 SP95/SP98）时取更便宜的
                if let old = station.prices[fuel], old.perLitre <= value { continue }
                station.prices[fuel] = FuelPrice(perLitre: value, currency: money.currencyCode ?? "CAD", updated: date)
            }
            return station
        }
    }
}

enum FuelFormat {
    /// 加拿大习惯：每升多少分，如 145.9¢
    static func price(_ p: FuelPrice) -> String {
        if p.currency == "CAD" || p.currency == "USD" {
            return String(format: "%.1f¢", p.perLitre * 100)
        }
        return String(format: "%.3f", p.perLitre)
    }

    static func money(_ v: Double) -> String { String(format: "$%.2f", v) }

    static func age(_ date: Date?) -> String? {
        guard let date else { return nil }
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        if minutes < 60 { return "\(max(minutes, 1)) 分钟前" }
        if minutes < 60 * 24 { return "\(minutes / 60) 小时前" }
        return "\(minutes / 60 / 24) 天前"
    }
}
