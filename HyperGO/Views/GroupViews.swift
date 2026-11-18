import SwiftUI
import SwiftData

// MARK: - 分组工具

enum PlaceGroups {
    /// 筛选值：空字符串 = 全部；`ungrouped` = 未分组；其他 = 分组名称
    static let all = ""
    static let ungrouped = "\u{1}未分组"

    /// 所有出现过的分组名称（按名称排序）
    static func names(in places: [Place]) -> [String] {
        Array(Set(places.map(\.groupName).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 按筛选值过滤；筛选的分组已不存在时视为「全部」
    static func filter(_ places: [Place], by filter: String) -> [Place] {
        switch filter {
        case all: return places
        case ungrouped:
            let matched = places.filter { $0.groupName.isEmpty }
            return matched.isEmpty ? places : matched
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
        }
        .buttonStyle(.plain)
    }
}

/// 顶部横向滑动的分组筛选条；没有任何分组时不显示
struct GroupFilterBar: View {
    let places: [Place]
    @Binding var selection: String

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
                                  selected: current(groups) == g) {
                            selection = g
                        }
                    }
                    if ungroupedCount > 0 {
                        GroupChip(title: "未分组", count: ungroupedCount,
                                  selected: current(groups) == PlaceGroups.ungrouped) {
                            selection = PlaceGroups.ungrouped
                        }
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

// MARK: - 分组管理

struct GroupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.sortIndex) private var places: [Place]

    @State private var newGroupName = ""
    @State private var showingNew = false
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var pendingNewGroup: String?

    var body: some View {
        NavigationStack {
            List {
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
                         : "点分组可以选择里面的地点；左滑可以重命名或删除。删除分组不会删除地点，只是把它们变成未分组。")
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { newGroupName = ""; showingNew = true } label: { Label("新建", systemImage: "plus") }
                }
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
