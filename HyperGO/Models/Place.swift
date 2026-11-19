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
    /// 所属分组名称；空字符串表示未分组（带默认值，旧数据可自动迁移）
    var groupName: String = ""
    /// 从相册选的照片（已裁成正方形缩小）；有照片时图标显示照片
    var photoData: Data? = nil

    init(name: String,
         icon: String = "mappin",
         colorHex: String = "#FF3B30",
         latitude: Double,
         longitude: Double,
         address: String = "",
         sortIndex: Int = 0,
         groupName: String = "") {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.groupName = groupName
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
