import SwiftUI
import SwiftData

// MARK: - 分组工具

enum PlaceGroups {
    /// 筛选值：空字符串 = 全部；`ungrouped` = 未分组；其他 = 分组名称
    static let all = ""
    static let ungrouped = "\u{1}未分组"

    /// 分组的自定义顺序（在「管理分组」里拖动调整），存在 UserDefaults
    static let orderKey = "groupOrder"
    static var order: [String] {
        get { (UserDefaults.standard.string(forKey: orderKey) ?? "").split(separator: "\n").map(String.init) }
        set { UserDefaults.standard.set(newValue.joined(separator: "\n"), forKey: orderKey) }
    }

    /// 所有出现过的分组名称：先按自定义顺序，没排过的按名称排在后面
    static func names(in places: [Place]) -> [String] {
        let order = self.order
        return Array(Set(places.map(\.groupName).filter { !$0.isEmpty })).sorted { a, b in
            let ia = order.firstIndex(of: a) ?? .max, ib = order.firstIndex(of: b) ?? .max
            return ia != ib ? ia < ib : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func rename(_ old: String, to new: String) {
        order = order.map { $0 == old ? new : $0 }
    }

    /// 按筛选值过滤；筛选的分组已被删除（名称不存在）时视为「全部」
    /// 「未分组」没有地点时返回空列表（不能退回全部，否则会把已分组的地点也显示出来）
    static func filter(_ places: [Place], by filter: String) -> [Place] {
        switch filter {
        case all: return places
        case ungrouped:
            return places.filter { $0.groupName.isEmpty }
        default:
            let matched = places.filter { $0.groupName == filter }
            return matched.isEmpty && !names(in: places).contains(filter) ? places : matched
        }
    }
}

// MARK: - 分组标签

struct GroupChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    /// 有地点拖到这个标签上方时高亮
    var targeted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                if let count {
                    Text("\(count)").foregroundStyle(selected ? .white.opacity(0.8) : .secondary).monospacedDigit()
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
            .overlay(Capsule().stroke(Color.accentColor, lineWidth: targeted ? 2.5 : 0))
            .scaleEffect(targeted ? 1.15 : 1)
            .animation(.snappy, value: targeted)
        }
        .buttonStyle(.plain)
    }
}

/// 顶部横向滑动的分组筛选条；没有任何分组时不显示
struct GroupFilterBar: View {
    let places: [Place]
    @Binding var selection: String
    /// 把地点拖到分组标签上时调用（参数是分组名称，「未分组」为空字符串）；nil 表示不接收拖放
    var onDropPlace: ((String) -> Void)? = nil
    @AppStorage(PlaceGroups.orderKey) private var orderRaw = ""   // 顺序变化时刷新
    @State private var targeted: String?

    var body: some View {
        let groups = PlaceGroups.names(in: places)
        if !groups.isEmpty {
            let ungroupedCount = places.filter { $0.groupName.isEmpty }.count
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GroupChip(title: "全部", count: places.count, selected: current(groups) == PlaceGroups.all) {
                        selection = PlaceGroups.all
                    }
                    ForEach(groups, id: \.self) { g in
                        GroupChip(title: g, count: places.filter { $0.groupName == g }.count,
                                  selected: current(groups) == g, targeted: targeted == g) {
                            selection = g
                        }
                        .modifier(ChipDrop(key: g, value: g, targeted: $targeted, onDrop: onDropPlace))
                    }
                    if ungroupedCount > 0 || onDropPlace != nil || selection == PlaceGroups.ungrouped {
                        GroupChip(title: "未分组", count: ungroupedCount,
                                  selected: current(groups) == PlaceGroups.ungrouped,
                                  targeted: targeted == PlaceGroups.ungrouped) {
                            selection = PlaceGroups.ungrouped
                        }
                        .modifier(ChipDrop(key: PlaceGroups.ungrouped, value: "", targeted: $targeted, onDrop: onDropPlace))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    /// 选中的分组被删掉后，显示为「全部」
    private func current(_ groups: [String]) -> String {
        if selection == PlaceGroups.all || selection == PlaceGroups.ungrouped || groups.contains(selection) {
            return selection
        }
        return PlaceGroups.all
    }
}

/// 分组标签作为拖放目标
private struct ChipDrop: ViewModifier {
    let key: String
    let value: String
    @Binding var targeted: String?
    let onDrop: ((String) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content.onDrop(of: [.plainText], isTargeted: Binding(
                get: { targeted == key },
                set: { on in targeted = on ? key : (targeted == key ? nil : targeted) }
            )) { _ in
                onDrop(value)
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - 分组管理

struct GroupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.sortIndex) private var places: [Place]

    @State private var newGroupName = ""
    @State private var showingNew = false
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var pendingNewGroup: String?
    @State private var selectedGroups = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmingDelete = false
    @AppStorage(PlaceGroups.orderKey) private var orderRaw = ""

    var body: some View {
        NavigationStack {
            List(selection: $selectedGroups) {
                let groups = PlaceGroups.names(in: places)
                Section {
                    ForEach(groups, id: \.self) { g in
                        NavigationLink {
                            GroupMembersView(groupName: g)
                        } label: {
                            LabeledContent(g, value: "\(places.filter { $0.groupName == g }.count) 个地点")
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(g) } label: { Label("删除分组", systemImage: "trash") }
                            Button { renameText = g; renaming = g } label: { Label("重命名", systemImage: "pencil") }
                                .tint(.orange)
                        }
                    }
                    .onMove { from, to in
                        var list = groups
                        list.move(fromOffsets: from, toOffset: to)
                        PlaceGroups.order = list
                        orderRaw = PlaceGroups.order.joined(separator: "\n")
                    }
                    if let pending = pendingNewGroup, !groups.contains(pending) {
                        NavigationLink {
                            GroupMembersView(groupName: pending)
                        } label: {
                            LabeledContent(pending, value: "还没有地点")
                        }
                    }
                } footer: {
                    Text(groups.isEmpty && pendingNewGroup == nil
                         ? "还没有分组。点右上角「+」创建一个，再选择要放进去的地点。"
                         : "点分组可以选择里面的地点；左滑可以重命名或删除；点「编辑」可以拖动调整顺序、多选批量删除。删除分组不会删除地点，只是把它们变成未分组。")
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !PlaceGroups.names(in: places).isEmpty {
                        Button(editMode.isEditing ? "好" : "编辑") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            selectedGroups.removeAll()
                        }
                    }
                    Button { newGroupName = ""; showingNew = true } label: { Label("新建", systemImage: "plus") }
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Text(selectedGroups.isEmpty ? "选择要删除的分组" : "删除 \(selectedGroups.count) 个分组")
                        }
                        .disabled(selectedGroups.isEmpty)
                    }
                }
            }
            .confirmationDialog("删除 \(selectedGroups.count) 个分组？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除分组", role: .destructive) {
                    for g in selectedGroups { delete(g) }
                    selectedGroups.removeAll()
                    editMode = .inactive
                }
            } message: {
                Text("里面的地点不会被删除，只会变成未分组。")
            }
            .alert("新建分组", isPresented: $showingNew) {
                TextField("分组名称", text: $newGroupName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let name = newGroupName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { pendingNewGroup = name }
                }
            } message: {
                Text("创建后点它，选择要放进这个分组的地点。")
            }
            .alert("重命名分组", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("分组名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if let old = renaming, !name.isEmpty {
                        for p in places where p.groupName == old { p.groupName = name }
                        PlaceGroups.rename(old, to: name)
                    }
                    renaming = nil
                }
            }
        }
    }

    private func delete(_ group: String) {
        for p in places where p.groupName == group { p.groupName = "" }
    }
}

/// 勾选某个分组包含哪些地点（一个地点只能在一个分组里）
struct GroupMembersView: View {
    let groupName: String
    @Query(sort: \Place.sortIndex) private var places: [Place]

    var body: some View {
        List {
            Section {
                ForEach(places) { place in
                    Button {
                        place.groupName = (place.groupName == groupName) ? "" : groupName
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: place.groupName == groupName ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(place.groupName == groupName ? Color.accentColor : Color.secondary)
                            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                if !place.groupName.isEmpty && place.groupName != groupName {
                                    Text("当前在「\(place.groupName)」").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("勾选的地点会放进「\(groupName)」。已经在其他分组里的地点会移过来。")
            }
        }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("全选") { for p in places { p.groupName = groupName } }
                    Button("只选未分组的") { for p in places where p.groupName.isEmpty { p.groupName = groupName } }
                    Button("全部取消", role: .destructive) {
                        for p in places where p.groupName == groupName { p.groupName = "" }
                    }
                } label: {
                    Image(systemName: "checklist")
                }
            }
        }
    }
}
