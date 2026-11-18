import Foundation
import SwiftData

/// 分组（首页显示成文件夹）。地点通过 Place.groupName 关联到分组名称。
@Model
final class PlaceGroup {
    var name: String
    /// SF Symbol 名称或单个 emoji；空字符串表示用组内地点的小图标拼成文件夹预览
    var icon: String = ""
    var colorHex: String = "#007AFF"
    var sortIndex: Int = 0

    init(name: String, icon: String = "", colorHex: String = "#007AFF", sortIndex: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

/// 分组相关的通用操作
@MainActor
enum GroupStore {
    /// 确保有这个名称的分组（没有就新建，放在最后）
    @discardableResult
    static func ensure(_ name: String, in context: ModelContext) -> PlaceGroup? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<PlaceGroup>())) ?? []
        if let existing = all.first(where: { $0.name == name }) { return existing }
        let colors = Presets.colors
        let group = PlaceGroup(name: name,
                               colorHex: colors[(all.count + 6) % colors.count],
                               sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(group)
        return group
    }

    /// 把地点放进分组（名称为空表示移出分组）
    static func assign(_ places: [Place], to name: String, in context: ModelContext) {
        let name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { ensure(name, in: context) }
        for p in places { p.groupName = name }
    }

    static func rename(_ group: PlaceGroup, to newName: String, places: [Place]) {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != group.name else { return }
        for p in places where p.groupName == group.name { p.groupName = newName }
        group.name = newName
    }

    /// 删除分组：组内地点变成未分组，地点本身不删
    static func delete(_ group: PlaceGroup, places: [Place], in context: ModelContext) {
        for p in places where p.groupName == group.name { p.groupName = "" }
        context.delete(group)
    }

    /// 旧版本只在地点上记分组名称：给这些名称补建分组，并沿用旧的排序
    static func migrateLegacy(in context: ModelContext) {
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let existing = Set(((try? context.fetch(FetchDescriptor<PlaceGroup>())) ?? []).map(\.name))
        let legacyOrder = (UserDefaults.standard.string(forKey: "groupOrder") ?? "")
            .split(separator: "\n").map(String.init)
        let missing = Set(places.map(\.groupName).filter { !$0.isEmpty }).subtracting(existing)
        guard !missing.isEmpty else { return }
        let sorted = missing.sorted { a, b in
            let ia = legacyOrder.firstIndex(of: a) ?? .max, ib = legacyOrder.firstIndex(of: b) ?? .max
            return ia != ib ? ia < ib : a.localizedStandardCompare(b) == .orderedAscending
        }
        for name in sorted { ensure(name, in: context) }
        try? context.save()
    }
}
