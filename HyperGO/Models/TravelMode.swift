import MapKit

/// 出行方式：目前只保留驾车
enum TravelMode: String, CaseIterable, Identifiable {
    case driving

    var id: String { rawValue }

    var title: String { "驾车" }

    var symbol: String { "car.fill" }

    /// 用于 App 内估算时间 / 道路距离
    var mkTransportType: MKDirectionsTransportType { .automobile }
}
