import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

/// 圆形彩色底 + SF Symbol 或 emoji；有照片时显示照片
struct PlaceIconView: View {
    let icon: String
    let colorHex: String
    var photo: Data? = nil
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let image = PlacePhoto.image(photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Circle().fill(Color(hex: colorHex))
                if UIImage(systemName: icon) != nil {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(icon).font(.system(size: size * 0.55))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// 地点照片：存之前裁成正方形、缩小，显示时缓存解码结果
enum PlacePhoto {
    private static let cache = NSCache<NSData, UIImage>()

    static func image(_ data: Data?) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 取中间正方形，缩到 300×300，存成 JPEG（每张约 20KB）
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let target: CGFloat = 300
        let scale = target / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return out.jpegData(compressionQuality: 0.8)
    }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) 米" }
        return String(format: "%.1f 公里", meters / 1000)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

enum Presets {
    static let symbols = [
        "house.fill", "building.2.fill", "briefcase.fill", "cart.fill",
        "fork.knife", "cup.and.saucer.fill", "fuelpump.fill", "car.fill",
        "p.circle.fill", "cross.case.fill", "graduationcap.fill", "dumbbell.fill",
        "tree.fill", "airplane", "tram.fill", "bag.fill",
        "gift.fill", "heart.fill", "star.fill", "flag.fill",
        "mappin", "person.2.fill", "pawprint.fill", "book.fill",
    ]

    /// 文件夹（分组）可选图案
    static let folderSymbols = [
        "folder.fill", "person.2.fill", "briefcase.fill", "cart.fill",
        "house.fill", "building.2.fill", "star.fill", "heart.fill",
        "shippingbox.fill", "pawprint.fill", "fork.knife", "cup.and.saucer.fill",
        "car.fill", "bag.fill", "gift.fill", "flag.fill",
        "graduationcap.fill", "cross.case.fill", "wrench.and.screwdriver.fill", "leaf.fill",
        "sun.max.fill", "moon.fill", "bolt.fill", "tag.fill",
    ]

    static let colors = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55",
        "#A2845E", "#8E8E93",
    ]
}
