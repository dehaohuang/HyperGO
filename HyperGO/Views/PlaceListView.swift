import SwiftUI
import SwiftData

/// 首页：分组文件夹 + 未分组的地点
struct PlaceListView: View {
    var body: some View {
        NavigationStack {
            PlaceBoard(folder: nil)
                .navigationDestination(for: PlaceGroup.self) { PlaceBoard(folder: $0) }
        }
    }
}

/// 图标网格页面。folder 为 nil 是首页（显示文件夹和未分组地点），否则是某个文件夹的内页
struct PlaceBoard: View {
    let folder: PlaceGroup?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex, animation: .snappy) private var places: [Place]
    @Query(sort: \PlaceGroup.sortIndex, animation: .snappy) private var groups: [PlaceGroup]
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving

    @State private var editingPlace: Place?
    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var showingImport = false
    @State private var routeDistances = RouteDistanceStore()
    @State private var showingGroups = false
    @State private var editingFolder: PlaceGroup?
    @State private var showingMembers = false
    @State private var confirmingDeleteFolder = false
    /// 「新建分组…」后要放进新分组的地点
    @State private var newGroupTargets: [Place] = []

    /// 拖动状态：原位置留空，其他图标实时让位
    @State private var drag = DragState()
    /// 地点拖到哪个文件夹上方（高亮）
    @State private var targetedFolder: PersistentIdentifier?

    /// 多选模式
    @State private var selecting = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var confirmingDelete = false

    /// 本页显示的地点：首页是未分组的，文件夹里是组内的
    private var visible: [Place] {
        if let folder { return places.filter { $0.groupName == folder.name } }
        return places.filter { $0.groupName.isEmpty }
    }
    private var folders: [PlaceGroup] { folder == nil ? groups : [] }
    private var selectedPlaces: [Place] { places.filter { selectedIDs.contains($0.id) } }
    private func members(of g: PlaceGroup) -> [Place] { places.filter { $0.groupName == g.name } }

    /// 一排最多 4 个图标
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
                ForEach(folders) { g in
                    folderTile(g)
                }
                ForEach(visible) { place in
                    tile(for: place)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, selecting ? 80 : 0)
        }
        // 拖到空白处松手时结束拖动
        .onDrop(of: [.plainText], delegate: ContainerDropDelegate(drag: drag))
        .task(id: distanceRefreshKey) {
            routeDistances.refresh(from: locationManager.location,
                                   to: visible.map(\.coordinate),
                                   mode: travelMode)
        }
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom) {
            if selecting { batchBar }
        }
        .navigationTitle(selecting ? "已选 \(selectedIDs.count) 个" : (folder?.name ?? "HyperGO"))
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingNew) { PlaceEditorView(place: nil, initialGroup: folder?.name ?? "") }
        .sheet(item: $editingPlace) { PlaceEditorView(place: $0) }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingImport) { ImportPlacesView() }
        .sheet(isPresented: $showingGroups) { GroupManagerView() }
        .sheet(item: $editingFolder) { GroupEditorView(group: $0) }
        .sheet(isPresented: $showingNewFolder) { GroupEditorView(group: nil) }
        .sheet(isPresented: $showingMembers) {
            if let folder {
                NavigationStack {
                    GroupMembersView(group: folder)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("完成") { showingMembers = false } }
                        }
                }
            }
        }
        .sheet(isPresented: Binding(get: { !newGroupTargets.isEmpty }, set: { if !$0 { newGroupTargets = [] } })) {
            let targets = newGroupTargets
            GroupEditorView(group: nil) { g in
                GroupStore.assign(targets, to: g.name, in: context)
                endSelecting()
            }
        }
        .confirmationDialog("删除 \(selectedIDs.count) 个地点？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                for p in selectedPlaces { context.delete(p) }
                endSelecting()
            }
        } message: {
            Text("删除后不能恢复。")
        }
        .confirmationDialog("删除分组「\(folder?.name ?? "")」？", isPresented: $confirmingDeleteFolder, titleVisibility: .visible) {
            Button("删除分组", role: .destructive) {
                if let folder {
                    dismiss()
                    GroupStore.delete(folder, places: places, in: context)
                }
            }
        } message: {
            Text("里面的地点不会被删除，会回到首页（未分组）。")
        }
    }

    // MARK: 空状态

    @ViewBuilder
    private var emptyState: some View {
        if let folder, visible.isEmpty {
            ContentUnavailableView {
                Label("「\(folder.name)」是空的", systemImage: "folder")
            } description: {
                Text("在首页把地点拖到这个文件夹上，或者点右上角「⋯」→「选择地点」。")
            } actions: {
                Button("选择地点") { showingMembers = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if folder == nil && places.isEmpty && groups.isEmpty {
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

    // MARK: 文件夹

    @ViewBuilder
    private func folderTile(_ g: PlaceGroup) -> some View {
        NavigationLink(value: g) {
            FolderTile(group: g, members: members(of: g), targeted: targetedFolder == g.id)
        }
        .buttonStyle(.plain)
        .disabled(selecting)
        .opacity(selecting ? 0.4 : 1)
        .contextMenu {
            Button { editingFolder = g } label: { Label("编辑分组", systemImage: "pencil") }
            Button(role: .destructive) {
                GroupStore.delete(g, places: places, in: context)
            } label: { Label("删除分组（保留地点）", systemImage: "trash") }
        }
        .onDrop(of: [.plainText], delegate: FolderDropDelegate(group: g, drag: drag, targeted: $targetedFolder) { place in
            withAnimation(.snappy) { GroupStore.assign([place], to: g.name, in: context) }
        })
    }

    // MARK: 单个地点

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
        groupMenu(for: [place], title: place.groupName.isEmpty ? "放进分组" : "分组：\(place.groupName)")
        if !place.groupName.isEmpty {
            Button {
                withAnimation(.snappy) { GroupStore.assign([place], to: "", in: context) }
            } label: { Label("移出分组", systemImage: "folder.badge.minus") }
        }
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
            ForEach(groups) { g in
                Button {
                    withAnimation(.snappy) { GroupStore.assign(targets, to: g.name, in: context) }
                    endSelecting()
                } label: {
                    if targets.count == 1 && targets[0].groupName == g.name { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
                }
            }
            Button { newGroupTargets = targets } label: {
                Label("新建分组…", systemImage: "plus")
            }
            if targets.contains(where: { !$0.groupName.isEmpty }) {
                Button {
                    withAnimation(.snappy) { GroupStore.assign(targets, to: "", in: context) }
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
        } else if let folder {
            ToolbarItem(placement: .topBarTrailing) {
                Button("选择") { withAnimation { selecting = true } }
                    .disabled(visible.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editingFolder = folder } label: { Label("编辑分组（名称、图案、颜色）", systemImage: "pencil") }
                    Button { showingMembers = true } label: { Label("选择地点", systemImage: "checklist") }
                    Button { showingNew = true } label: { Label("在这个分组里添加地点", systemImage: "mappin.and.ellipse") }
                    Button(role: .destructive) { confirmingDeleteFolder = true } label: {
                        Label("删除分组", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("选择") { withAnimation { selecting = true } }
                    .disabled(visible.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNew = true } label: { Label("添加地点", systemImage: "mappin.and.ellipse") }
                    Button { showingNewFolder = true } label: { Label("新建分组", systemImage: "folder.badge.plus") }
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

    @State private var showingNewFolder = false

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

    /// 位置（约 100 米精度）、出行方式或地点变化时重新计算道路距离
    private var distanceRefreshKey: String {
        let loc = locationManager.location.map {
            String(format: "%.3f,%.3f", $0.coordinate.latitude, $0.coordinate.longitude)
        } ?? "none"
        let dests = visible.map { RouteDistanceStore.key($0.coordinate) }.joined(separator: ";")
        return "\(loc)|\(travelMode.rawValue)|\(dests)"
    }
}

/// 地点拖到文件夹上：高亮，松手放进这个分组
private struct FolderDropDelegate: DropDelegate {
    let group: PlaceGroup
    let drag: DragState
    @Binding var targeted: PersistentIdentifier?
    let assign: (Place) -> Void

    func dropEntered(info: DropInfo) {
        drag.touch()
        if drag.source != nil { targeted = group.id }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.touch()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if targeted == group.id { targeted = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        if let place = drag.source { assign(place) }
        drag.end()
        return true
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
