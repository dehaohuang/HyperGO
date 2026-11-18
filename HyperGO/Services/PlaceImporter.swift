import Foundation
import CoreLocation
import SwiftData

/// 批量导入地点
/// 每行一个：`名称<TAB>地址`，也可以是 `名称<TAB>地址<TAB>纬度<TAB>经度`（带坐标时不再查地址）
/// 没有 TAB 时，用连续两个以上空格分隔名称和地址
@MainActor
enum PlaceImporter {
    struct Entry {
        let name: String
        let address: String
        var coordinate: CLLocationCoordinate2D?
    }

    struct Result {
        var added: [String] = []
        var duplicates: [String] = []
        var failed: [String] = []   // 地址查不到的「名称（地址）」

        var summary: String {
            var parts = ["已导入 \(added.count) 个地点"]
            if !duplicates.isEmpty { parts.append("跳过已存在的 \(duplicates.count) 个") }
            if !failed.isEmpty { parts.append("\(failed.count) 个地址没找到：\n" + failed.joined(separator: "\n")) }
            return parts.joined(separator: "\n")
        }
    }

    /// App 文稿目录里的导入文件；放进来后，下次打开 App 自动导入并删除
    static var dropFileURL: URL {
        URL.documentsDirectory.appending(path: "import.txt")
    }

    static func parse(_ text: String) -> [Entry] {
        text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            var fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.count < 2, let r = line.range(of: #"\s{2,}"#, options: .regularExpression) {
                fields = [String(line[..<r.lowerBound]), String(line[r.upperBound...])]
            }
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            var entry = Entry(name: fields[0], address: fields[1].replacingOccurrences(of: "，", with: ", "))
            if fields.count >= 4, let lat = Double(fields[2]), let lon = Double(fields[3]) {
                entry.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return entry
        }
    }

    /// 导入文本；near 用于地址查询时优先匹配附近（一般传当前位置）
    static func importText(_ text: String, into context: ModelContext, near: CLLocation?,
                           groupName: String = "",
                           progress: ((Int, Int) -> Void)? = nil) async -> Result {
        let entries = parse(text)
        var result = Result()
        let existing = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        var known = Set(existing.map { key($0.name, $0.address) })
        var nextIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        let geocoder = CLGeocoder()
        GroupStore.ensure(groupName, in: context)
        let region = near.map { CLCircularRegion(center: $0.coordinate, radius: 80_000, identifier: "near") }

        for (i, entry) in entries.enumerated() {
            progress?(i, entries.count)
            let k = key(entry.name, entry.address)
            if known.contains(k) {
                result.duplicates.append(entry.name)
                continue
            }
            var coordinate = entry.coordinate
            if coordinate == nil {
                coordinate = try? await geocoder.geocodeAddressString(entry.address, in: region).first?.location?.coordinate
                try? await Task.sleep(for: .milliseconds(300))   // 避免查询太快被限流
            }
            guard let coordinate else {
                result.failed.append("\(entry.name)（\(entry.address)）")
                continue
            }
            let color = Presets.colors[nextIndex % Presets.colors.count]
            context.insert(Place(name: entry.name, icon: "person.fill", colorHex: color,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude,
                                 address: entry.address, sortIndex: nextIndex,
                                 groupName: groupName))
            nextIndex += 1
            known.insert(k)
            result.added.append(entry.name)
        }
        progress?(entries.count, entries.count)
        try? context.save()
        return result
    }

    /// 如果文稿目录里有 import.txt，就导入它并删除文件
    static func importDropFileIfPresent(into context: ModelContext, near: CLLocation?) async -> Result? {
        let url = dropFileURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return await importText(text, into: context, near: near)
    }

    private static func key(_ name: String, _ address: String) -> String {
        (name + "|" + address).lowercased().replacingOccurrences(of: " ", with: "")
    }
}
