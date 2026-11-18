import AppIntents
import SwiftData
import Foundation

/// App 和 Siri 指令共用的数据库
@MainActor
enum AppData {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: Place.self, PlaceGroup.self) }
        catch { fatalError("无法打开数据库：\(error)") }
    }()
}

/// Siri 指令打开 App 后要做的事（切到路线页并规划某个分组）
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    struct RouteRequest: Equatable {
        let id = UUID()
        /// 分组名称；空字符串表示全部地点
        let groupName: String
    }

    /// 当前标签页：0 地点、1 地图、2 路线
    var tab = 0
    var routeRequest: RouteRequest?

    func planRoute(group: String) {
        tab = 2
        routeRequest = RouteRequest(groupName: group)
    }
}

// MARK: - 地点

struct PlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "地点"
    static let defaultQuery = PlaceQuery()

    /// 用地点名称当编号（Siri 里也是说名称）
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct PlaceQuery: EntityStringQuery {
    @MainActor
    private func all() -> [Place] {
        (try? AppData.container.mainContext.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [PlaceEntity] {
        let names = Set(all().map(\.name))
        return identifiers.filter(names.contains).map(PlaceEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlaceEntity] {
        let key = string.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        return all().map(\.name)
            .filter { $0.lowercased().contains(key) || key.contains($0.lowercased()) }
            .filter { seen.insert($0).inserted }
            .map(PlaceEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaceEntity] {
        var seen = Set<String>()
        return all().map(\.name).filter { seen.insert($0).inserted }.map(PlaceEntity.init)
    }
}

struct NavigateToPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "导航到地点"
    static let description = IntentDescription("用设置里选的地图 App 导航到某个地点")
    static let openAppWhenRun = true

    @Parameter(title: "地点", requestValueDialog: "要导航到哪个地点？")
    var place: PlaceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let all = (try? AppData.container.mainContext.fetch(FetchDescriptor<Place>())) ?? []
        guard let target = all.first(where: { $0.name == place.id }) else {
            return .result(dialog: "没有找到「\(place.id)」")
        }
        // 等 App 回到前台后再跳转地图 App
        try? await Task.sleep(for: .milliseconds(600))
        Navigator.navigate(to: target.coordinate)
        return .result(dialog: "正在导航到\(target.name)")
    }
}

// MARK: - 分组路线

struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "分组"
    static let defaultQuery = GroupQuery()

    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct GroupQuery: EntityStringQuery {
    @MainActor
    private func names() -> [String] {
        let groups = (try? AppData.container.mainContext.fetch(FetchDescriptor<PlaceGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return groups.map(\.name)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [GroupEntity] {
        let all = Set(names())
        return identifiers.filter(all.contains).map(GroupEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        let key = string.trimmingCharacters(in: .whitespaces).lowercased()
        return names().filter { $0.lowercased().contains(key) || key.contains($0.lowercased()) }.map(GroupEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        names().map(GroupEntity.init)
    }
}

struct PlanGroupRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "规划分组路线"
    static let description = IntentDescription("打开 HyperGO，算出某个分组里所有地点的最短访问顺序")
    static let openAppWhenRun = true

    @Parameter(title: "分组", requestValueDialog: "要规划哪个分组的路线？")
    var group: GroupEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentRouter.shared.planRoute(group: group.id)
        return .result(dialog: "正在规划「\(group.id)」的路线")
    }
}

// MARK: - Siri 短语

struct HyperGOShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NavigateToPlaceIntent(), phrases: [
            "用\(.applicationName)导航到\(\.$place)",
            "\(.applicationName)导航到\(\.$place)",
            "用\(.applicationName)去\(\.$place)",
            "\(.applicationName)去\(\.$place)",
            "用\(.applicationName)导航",
            "\(.applicationName)导航",
        ], shortTitle: "导航到地点", systemImageName: "location.fill")
        AppShortcut(intent: PlanGroupRouteIntent(), phrases: [
            "用\(.applicationName)规划\(\.$group)路线",
            "\(.applicationName)规划\(\.$group)路线",
            "用\(.applicationName)规划\(\.$group)的路线",
            "用\(.applicationName)规划路线",
            "\(.applicationName)规划路线",
        ], shortTitle: "规划分组路线", systemImageName: "point.topleft.down.to.point.bottomright.curvepath")
    }
}
