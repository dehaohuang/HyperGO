import Foundation
import SwiftData
import CoreLocation

@Model
final class Place {
    var name: String
    /// SF Symbol 名称或单个 emoji
    var icon: String
    var colorHex: String
    var latitude: Double
    var longitude: Double
    var address: String
    var sortIndex: Int
    var createdAt: Date

    init(name: String,
         icon: String = "mappin",
         colorHex: String = "#FF3B30",
         latitude: Double,
         longitude: Double,
         address: String = "",
         sortIndex: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
