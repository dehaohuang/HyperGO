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

    /// 拖动：长按后移动手指，图标跟着手指走，其他图标带动画让位
    @State private var dragID: PersistentIdentifier?
    /// 拖动开始时图标中心和大小（网格坐标）
    @State private var dragStart: CGPoint = .zero
    @State private var dragSize: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    /// 拿起时放大；放进文件夹时缩小淡出
    @State private var lifted = false
    @State private var sinking = false
    @GestureState private var pressing = false
    /// 长按住的图标（稍微放大提示）；不移动就松手则弹出菜单
    @State private var pressedID: PersistentIdentifier?
    @State private var menuID: PersistentIdentifier?
    @State private var longPressTime = Date.distantPast
    /// 每个图标、文件夹在网格里的位置
    @State private var tileFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var folderFrames: [PersistentIdentifier: CGRect] = [:]
    /// 地点拖到哪个文件夹上方（高亮）
    @State private var targetedFolder: PersistentIdentifier?
    private static let space = "board"

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
            .coordinateSpace(.named(Self.space))
            .overlay(alignment: .topLeading) { floatingTile }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, selecting ? 80 : 0)
        }
        .scrollDisabled(dragID != nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: pressedID) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: targetedFolder) { _, new in new != nil }
        // 手势被系统打断（比如弹出长按菜单）时也要结束拖动
        .onChange(of: pressing) { _, now in
            if !now {
                withAnimation(.snappy) { pressedID = nil }
                endDrag()
            }
        }
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { folderFrames[g.id] = $0 }
        .onDisappear { folderFrames[g.id] = nil }
    }

    // MARK: 单个地点

    @ViewBuilder
    private func tile(for place: Place) -> some View {
        let isSelected = selectedIDs.contains(place.id)
        let base = PlaceTile(place: place,
                  routeDistance: routeDistances.distance(to: place.coordinate),
                  straightDistance: locationManager.distance(to: place.coordinate),
                  placeholder: dragID == place.id)
            .scaleEffect(pressedID == place.id && dragID == nil ? 1.1 : 1)
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tileFrames[place.id] = $0 }
            .onDisappear { tileFrames[place.id] = nil }
            .onTapGesture {
                // 长按过（拖动或弹菜单）就不算点击
                guard dragID == nil, menuID == nil, pressedID == nil, Date.now.timeIntervalSince(longPressTime) > 0.8 else { return }
                if selecting {
                    if isSelected { selectedIDs.remove(place.id) } else { selectedIDs.insert(place.id) }
                } else {
                    GoogleMaps.navigate(to: place.coordinate, mode: travelMode)
                }
            }
        pressInteraction(base, place: place)
            .popover(isPresented: Binding(get: { menuID == place.id },
                                          set: { if !$0, menuID == place.id { menuID = nil } })) {
                placeMenu(for: place)
                    .presentationCompactAdaptation(.popover)
            }
    }

    /// 被拖动的图标：跟着手指移动，浮在其他图标上面
    @ViewBuilder
    private var floatingTile: some View {
        if let id = dragID, let place = places.first(where: { $0.id == id }) {
            PlaceTile(place: place,
                      routeDistance: routeDistances.distance(to: place.coordinate),
                      straightDistance: locationManager.distance(to: place.coordinate))
                .frame(width: dragSize.width, height: dragSize.height)
                .scaleEffect(sinking ? 0.25 : (lifted ? 1.15 : 1))
                .opacity(sinking ? 0 : 1)
                .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 10, y: 6)
                .position(x: dragStart.x + dragTranslation.width,
                          y: dragStart.y + dragTranslation.height)
                .allowsHitTesting(false)
        }
    }

    /// 长按松手后弹出的菜单（放在图标旁边的小气泡里）
    private func placeMenu(for place: Place) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("编辑", "pencil") { editingPlace = place }
            Divider()
            Menu {
                ForEach(groups) { g in
                    Button {
                        menuID = nil
                        withAnimation(.snappy) { GroupStore.assign([place], to: g.name, in: context) }
                    } label: {
                        if place.groupName == g.name { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
                    }
                }
                Button {
                    menuID = nil
                    after { newGroupTargets = [place] }
                } label: { Label("新建分组…", systemImage: "plus") }
            } label: {
                menuLabel(place.groupName.isEmpty ? "放进分组" : "分组：\(place.groupName)", "folder", chevron: true)
            }
            if !place.groupName.isEmpty {
                Divider()
                menuRow("移出分组", "folder.badge.minus") {
                    withAnimation(.snappy) { GroupStore.assign([place], to: "", in: context) }
                }
            }
            Divider()
            menuRow("多选", "checkmark.circle") {
                withAnimation {
                    selecting = true
                    selectedIDs = [place.id]
                }
            }
            Divider()
            menuRow("删除", "trash", destructive: true) {
                withAnimation(.snappy) { context.delete(place) }
            }
        }
        .frame(width: 230)
    }

    private func menuRow(_ title: String, _ icon: String, destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button {
            menuID = nil
            after(action)
        } label: {
            menuLabel(title, icon, destructive: destructive)
        }
    }

    private func menuLabel(_ title: String, _ icon: String, destructive: Bool = false, chevron: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if chevron { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary) }
            Image(systemName: icon).frame(width: 24)
        }
        .foregroundStyle(destructive ? Color.red : Color.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// 等菜单气泡收起后再执行（避免和弹出页面冲突）
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
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
        withAnimation {
            selecting = false
            selectedIDs.removeAll()
        }
    }

    // MARK: 拖动

    /// 长按 0.3 秒图标放大：移动手指开始拖动，不移动直接松手则弹出菜单（iOS 17 用）
    private func dragGesture(for place: Place) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let d) = value else { return }
                pressBegan(place)
                if let d { pressMoved(place, d.translation) }
            }
            .onEnded { _ in pressEnded(place) }
    }

    /// 长按拖动：iOS 18 起用系统的长按识别器，不会挡住列表滚动
    @ViewBuilder
    private func pressInteraction<V: View>(_ content: V, place: Place) -> some View {
        if selecting {
            content
        } else if #available(iOS 18.0, *) {
            content.gesture(LongPressDragRecognizer(space: Self.space) { state, translation in
                switch state {
                case .began: pressBegan(place)
                case .changed: pressMoved(place, translation)
                case .ended: pressEnded(place)
                default: pressCancelled()
                }
            })
        } else {
            content.gesture(dragGesture(for: place))
        }
    }

    private func pressBegan(_ place: Place) {
        guard pressedID != place.id, dragID == nil else { return }
        longPressTime = .now
        withAnimation(.snappy(duration: 0.2)) { pressedID = place.id }
    }

    private func pressMoved(_ place: Place, _ translation: CGSize) {
        if dragID == nil {
            // 移动一点距离才算开始拖动，否则松手弹出菜单
            guard hypot(translation.width, translation.height) > 6 else { return }
            beginDrag(place)
        }
        guard dragID == place.id else { return }
        dragTranslation = translation
        dragMoved(place)
    }

    private func pressEnded(_ place: Place) {
        if pressedID == place.id {
            longPressTime = .now
            if dragID == nil { menuID = place.id }
        }
        withAnimation(.snappy) { pressedID = nil }
        endDrag()
    }

    private func pressCancelled() {
        withAnimation(.snappy) { pressedID = nil }
        endDrag()
    }

    private func beginDrag(_ place: Place) {
        guard let frame = tileFrames[place.id] else { return }
        dragStart = CGPoint(x: frame.midX, y: frame.midY)
        dragSize = frame.size
        dragTranslation = .zero
        sinking = false
        dragID = place.id
        withAnimation(.snappy(duration: 0.2)) { lifted = true }
    }

    /// 手指经过文件夹时高亮；经过其他图标时换位
    private func dragMoved(_ place: Place) {
        let p = CGPoint(x: dragStart.x + dragTranslation.width, y: dragStart.y + dragTranslation.height)
        if let g = folders.first(where: { folderFrames[$0.id]?.insetBy(dx: 6, dy: 6).contains(p) == true }) {
            if targetedFolder != g.id { withAnimation(.snappy) { targetedFolder = g.id } }
            return
        }
        if targetedFolder != nil { withAnimation(.snappy) { targetedFolder = nil } }
        guard let target = visible.first(where: {
            $0.id != place.id && tileFrames[$0.id]?.insetBy(dx: 8, dy: 8).contains(p) == true
        }) else { return }
        withAnimation(.snappy(duration: 0.3)) { moveLive(place, to: target) }
    }

    /// 松手：放进文件夹，或者滑回空出来的位置
    private func endDrag() {
        guard let id = dragID else { return }
        let place = places.first(where: { $0.id == id })
        if let gid = targetedFolder, let g = groups.first(where: { $0.id == gid }),
           let folderFrame = folderFrames[gid], let place {
            withAnimation(.snappy(duration: 0.25)) {
                dragTranslation = CGSize(width: folderFrame.midX - dragStart.x, height: folderFrame.midY - dragStart.y)
                sinking = true
            } completion: {
                withAnimation(.snappy) {
                    GroupStore.assign([place], to: g.name, in: context)
                    targetedFolder = nil
                }
                finishDrag(id)
            }
        } else if let slot = tileFrames[id] {
            withAnimation(.snappy(duration: 0.25)) {
                dragTranslation = CGSize(width: slot.midX - dragStart.x, height: slot.midY - dragStart.y)
                lifted = false
            } completion: {
                finishDrag(id)
            }
        } else {
            finishDrag(id)
        }
    }

    private func finishDrag(_ id: PersistentIdentifier) {
        guard dragID == id else { return }
        dragID = nil
        dragTranslation = .zero
        lifted = false
        sinking = false
        try? context.save()
    }

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

/// 系统长按识别器：按住 0.3 秒后开始，手指移动时持续报告位移；移动过早则让给列表滚动
@available(iOS 18.0, *)
private struct LongPressDragRecognizer: UIGestureRecognizerRepresentable {
    let space: String
    let action: (UIGestureRecognizer.State, CGSize) -> Void

    final class Coordinator { var start: CGPoint = .zero }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.3
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let p = context.converter.location(in: .named(space))
        if recognizer.state == .began { context.coordinator.start = p }
        let s = context.coordinator.start
        action(recognizer.state, CGSize(width: p.x - s.x, height: p.y - s.y))
    }
}
