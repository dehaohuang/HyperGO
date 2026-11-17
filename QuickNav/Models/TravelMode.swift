import MapKit

enum TravelMode: String, CaseIterable, Identifiable {
    case driving, walking, bicycling, transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driving: "驾车"
        case .walking: "步行"
        case .bicycling: "骑行"
        case .transit: "公交"
        }
    }

    var symbol: String {
        switch self {
        case .driving: "car.fill"
        case .walking: "figure.walk"
        case .bicycling: "bicycle"
        case .transit: "tram.fill"
        }
    }

    /// 用于 App 内估算时间/道路距离（骑行 MapKit 不支持，返回 nil）
    var mkTransportType: MKDirectionsTransportType? {
        switch self {
        case .driving: .automobile
        case .walking: .walking
        case .transit: .transit
        case .bicycling: nil
        }
    }
}
