import SwiftUI
import SwiftData

struct PlaceListView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex, animation: .snappy) private var places: [Place]
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving

    @State private var editingPlace: Place?
    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var showingImport = false
    @State private var routeDistances = RouteDistanceStore()
    @State private var showingGroups = false
    @AppStorage("groupFilter") private var groupFilter = PlaceGroups.all
    /// 「新建分组…」要放进新分组的地点（单个或批量）
    @State private var groupingTargets: [Place] = []
    @State private var newGroupText = ""

    /// 拖动状态：原位置留空，其他图标实时让位
    @State private var drag = DragState()

    /// 多选模式
    @State private var selecting = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var confirmingDelete = false

    /// 按分组筛选后要显示的地点
    private var visible: [Place] { PlaceGroups.filter(places, by: groupFilter) }
    private var selectedPlaces: [Place] { places.filter { selectedIDs.contains($0.id) } }

    /// 一排最多 4 个图标
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                GroupFilterBar(places: places, selection: $groupFilter,
                               onDropPlace: selecting ? nil : { group in dropDragged(onGroup: group) })
                LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
                    ForEach(visible) { place in
                        tile(for: place)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, selecting ? 80 : 0)
            }
            // 拖到空白处松手、或拖出列表时，结束拖动状态
            .onDrop(of: [.plainText], delegate: ContainerDropDelegate(drag: drag))
            .task(id: distanceRefreshKey) {
                routeDistances.refresh(from: locationManager.location,
                                       to: visible.map(\.coordinate),
                                       mode: travelMode)
            }
            .overlay {
                if !places.isEmpty && visible.isEmpty && groupFilter == PlaceGroups.ungrouped {
                    ContentUnavailableView {
                        Label("没有未分组的地点", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("所有地点都已经放进分组了。把地点拖到上面的「未分组」标签上，就能把它移出分组。")
                    }
                } else if places.isEmpty {
                    ContentUnavailableView {
                        Label("还没有地点", systemImage: "mappin.slash")
                    } description: {
                        Text("点右上角 + 添加你常去的地方，之后点一下就能用 Google 地图导航。")
                    } actions: {
                        Button("添加地点") { showingNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { batchBar }
            }
            .navigationTitle(selecting ? "已选 \(selectedIDs.count) 个" : "HyperGO")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingNew) { PlaceEditorView(place: nil) }
            .sheet(item: $editingPlace) { PlaceEditorView(place: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingImport) { ImportPlacesView() }
            .sheet(isPresented: $showingGroups) { GroupManagerView() }
            .alert("新建分组", isPresented: Binding(get: { !groupingTargets.isEmpty }, set: { if !$0 { groupingTargets = [] } })) {
                TextField("分组名称", text: $newGroupText)
                Button("取消", role: .cancel) { groupingTargets = [] }
                Button("放进这个分组") {
                    let name = newGroupText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { for p in groupingTargets { p.groupName = name } }
                    groupingTargets = []
                    endSelecting()
                }
            } message: {
                Text(groupingTargets.count == 1
                     ? "把「\(groupingTargets.first?.name ?? "")」放进新的分组。"
                     : "把选中的 \(groupingTargets.count) 个地点放进新的分组。")
            }
            .confirmationDialog("删除 \(selectedIDs.count) 个地点？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    for p in selectedPlaces { context.delete(p) }
                    endSelecting()
                }
            } message: {
                Text("删除后不能恢复。")
            }
        }
    }

    // MARK: 单个图标

    @ViewBuilder
    private func tile(for place: Place) -> some View {
        let isSelected = selectedIDs.contains(place.id)
        Button {
            drag.end()
            if selecting {
                if isSelected { selectedIDs.remove(place.id) } else { selectedIDs.insert(place.id) }
            } else {
                GoogleMaps.navigate(to: place.coordinate, mode: travelMode)
            }
        } label: {
            PlaceTile(place: place,
                      routeDistance: routeDistances.distance(to: place.coordinate),
                      straightDistance: locationManager.distance(to: place.coordinate),
                      placeholder: drag.showsPlaceholder && drag.source?.id == place.id)
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .background(Circle().fill(.background))
                            .offset(x: -6, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .modifier(TileInteractions(
            enabled: !selecting,
            place: place,
            drag: drag,
            move: moveLive,
            menu: { contextMenu(for: place) }
        ))
    }

    @ViewBuilder
    private func contextMenu(for place: Place) -> some View {
        Button { editingPlace = place } label: { Label("编辑", systemImage: "pencil") }
        groupMenu(for: [place], title: place.groupName.isEmpty ? "分组" : "分组：\(place.groupName)")
        Button {
            selecting = true
            selectedIDs = [place.id]
        } label: { Label("多选", systemImage: "checkmark.circle") }
        Button(role: .destructive) { context.delete(place) } label: { Label("删除", systemImage: "trash") }
    }

    /// 「移到分组」菜单，单个和批量共用
    @ViewBuilder
    private func groupMenu(for targets: [Place], title: String) -> some View {
        Menu {
            ForEach(PlaceGroups.names(in: places), id: \.self) { g in
                Button {
                    for p in targets { p.groupName = g }
                    endSelecting()
                } label: {
                    if targets.count == 1 && targets[0].groupName == g { Label(g, systemImage: "checkmark") } else { Text(g) }
                }
            }
            Button { newGroupText = ""; groupingTargets = targets } label: {
                Label("新建分组…", systemImage: "plus")
            }
            if targets.contains(where: { !$0.groupName.isEmpty }) {
                Button {
                    for p in targets { p.groupName = "" }
                    endSelecting()
                } label: { Label("移出分组", systemImage: "minus.circle") }
            }
        } label: {
            Label(title, systemImage: "folder")
        }
    }

    // MARK: 多选

    private var batchBar: some View {
        HStack(spacing: 12) {
            groupMenu(for: selectedPlaces, title: "移到分组")
                .buttonStyle(.bordered)
            Spacer()
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .disabled(selectedIDs.isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected = !visible.isEmpty && visible.allSatisfy { selectedIDs.contains($0.id) }
                Button(allSelected ? "全不选" : "全选") {
                    if allSelected { selectedIDs.removeAll() } else { selectedIDs = Set(visible.map(\.id)) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { endSelecting() }.bold()
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("选择") { withAnimation { selecting = true } }
                    .disabled(places.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNew = true } label: { Label("添加地点", systemImage: "mappin.and.ellipse") }
                    Button { showingImport = true } label: { Label("批量导入", systemImage: "square.and.arrow.down.on.square") }
                    Button { showingGroups = true } label: { Label("管理分组", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                } primaryAction: {
                    showingNew = true
                }
            }
        }
    }

    private func endSelecting() {
        drag.end()
        withAnimation {
            selecting = false
            selectedIDs.removeAll()
        }
    }

    // MARK: 拖动

    /// 拖动经过另一个图标时立即换位（其他图标带动画让开）
    private func moveLive(_ item: Place, to target: Place) {
        guard item.id != target.id,
              let from = places.firstIndex(of: item),
              let to = places.firstIndex(of: target) else { return }
        var items = places
        items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for (i, p) in items.enumerated() where p.sortIndex != i { p.sortIndex = i }
    }

    /// 把正在拖动的地点放进分组标签对应的分组
    private func dropDragged(onGroup group: String) {
        guard let place = drag.source else { return }
        withAnimation(.snappy) { place.groupName = group }
        drag.end()
    }

    /// 位置（约 100 米精度）、出行方式或地点变化时重新计算道路距离
    private var distanceRefreshKey: String {
        let loc = locationManager.location.map {
            String(format: "%.3f,%.3f", $0.coordinate.latitude, $0.coordinate.longitude)
        } ?? "none"
        let dests = visible.map { RouteDistanceStore.key($0.coordinate) }.joined(separator: ";")
        return "\(loc)|\(travelMode.rawValue)|\(dests)"
    }
}

/// 拖动状态。SwiftUI 没有「拖动结束」回调，所以原位置的空位按拖动活动显示：
/// 有拖放事件时留空，松手或 2.5 秒没有拖动事件就恢复显示，避免图标消失卡住
@MainActor
@Observable
final class DragState {
    /// 被拖动的地点（用于换位和归组）
    private(set) var source: Place?
    private(set) var showsPlaceholder = false
    @ObservationIgnored private var lastActivity = Date.distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    func begin(_ place: Place) {
        source = place
        touch()
    }

    /// 拖动仍在进行（进入或经过某个拖放目标）
    func touch() {
        guard source != nil else { return }
        lastActivity = .now
        if !showsPlaceholder { withAnimation(.snappy) { showsPlaceholder = true } }
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if Date.now.timeIntervalSince(self.lastActivity) > 2.5 {
                    withAnimation(.snappy) { self.showsPlaceholder = false }
                    self.watchdog = nil
                    return
                }
            }
        }
    }

    func end() {
        watchdog?.cancel()
        watchdog = nil
        if showsPlaceholder { withAnimation(.snappy) { showsPlaceholder = false } }
        source = nil
    }
}

/// 图标的拖动和长按菜单（多选模式下关闭）
private struct TileInteractions<Menu: View>: ViewModifier {
    let enabled: Bool
    let place: Place
    let drag: DragState
    let move: (Place, Place) -> Void
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu { menu() }
                .onDrag {
                    drag.begin(place)
                    return NSItemProvider(object: place.name as NSString)
                } preview: {
                    PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 64)
                        .contentShape(.dragPreview, Circle())
                }
                .onDrop(of: [.plainText], delegate: TileDropDelegate(target: place, drag: drag, move: move))
        } else {
            content
        }
    }
}

/// 拖到某个图标上方时让它们换位
private struct TileDropDelegate: DropDelegate {
    let target: Place
    let drag: DragState
    let move: (Place, Place) -> Void

    func dropEntered(info: DropInfo) {
        drag.touch()
        guard let item = drag.source, item.id != target.id else { return }
        move(item, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.touch()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.end()
        return true
    }
}

/// 列表空白处：松手结束拖动
private struct ContainerDropDelegate: DropDelegate {
    let drag: DragState

    func dropEntered(info: DropInfo) { drag.touch() }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.touch()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.end()
        return true
    }
}

/// 主屏幕风格的图标：彩色圆形图标 + 名称 + 距离
struct PlaceTile: View {
    @AppStorage("textSize") private var textSize: TextSize = .system
    let place: Place
    /// 最短实际道路距离（还没算好时为 nil）
    let routeDistance: Double?
    /// 直线距离，道路距离算好前先用「≈」显示
    let straightDistance: Double?
    /// 正在被拖走：原位置留空（其他图标照常让位）
    var placeholder: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 60)
            Text(place.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let routeDistance {
                Text(Format.distance(routeDistance))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            } else if let straightDistance {
                Text("≈" + Format.distance(straightDistance))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .opacity(placeholder ? 0 : 1)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .appTextSize(textSize)   // 设置里的字体大小只作用于图标文字
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("textSize") private var textSize: TextSize = .system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("字体大小", selection: $textSize) {
                        ForEach(TextSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                } header: {
                    Text("字体大小")
                } footer: {
                    Text("只调整首页图标下面的名称、距离，以及地图上地点的名称。「跟随系统」使用 iPhone 设置 → 显示与亮度 → 文字大小。")
                }
                Section("Google 地图") {
                    LabeledContent("App 状态", value: GoogleMaps.isAppInstalled ? "已安装" : "未安装（将使用网页版）")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
