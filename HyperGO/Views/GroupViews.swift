import SwiftUI
import SwiftData

// MARK: - 分组筛选（地图、路线页用，可多选）

enum PlaceGroups {
    /// 「未分组」在多选集合里的标记
    static let ungrouped = "\u{1}未分组"

    /// 选中的集合为空表示全部；否则保留属于选中分组（或未分组）的地点
    static func filter(_ places: [Place], by selection: Set<String>) -> [Place] {
        guard !selection.isEmpty else { return places }
        return places.filter { p in
            p.groupName.isEmpty ? selection.contains(ungrouped) : selection.contains(p.groupName)
        }
    }

    /// 多选集合与 @AppStorage 字符串互转
    static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }
    static func encode(_ set: Set<String>) -> String {
        set.sorted().joined(separator: "\n")
    }
}

/// 分组标签
struct GroupChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
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
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
    }
}

/// 可多选的分组筛选条：「全部」= 不筛选；点分组切换选中；没有任何分组时不显示
struct MultiGroupFilterBar: View {
    let places: [Place]
    let groups: [PlaceGroup]
    @Binding var selection: Set<String>

    var body: some View {
        if !groups.isEmpty {
            let ungroupedCount = places.filter { $0.groupName.isEmpty }.count
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GroupChip(title: "全部", count: places.count, selected: selection.isEmpty) {
                        selection = []
                    }
                    ForEach(groups) { g in
                        GroupChip(title: g.name, count: places.filter { $0.groupName == g.name }.count,
                                  selected: selection.contains(g.name)) {
                            toggle(g.name)
                        }
                    }
                    if ungroupedCount > 0 || selection.contains(PlaceGroups.ungrouped) {
                        GroupChip(title: "未分组", count: ungroupedCount,
                                  selected: selection.contains(PlaceGroups.ungrouped)) {
                            toggle(PlaceGroups.ungrouped)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func toggle(_ key: String) {
        if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
    }
}

// MARK: - 文件夹图标

/// 文件夹图标：设置了自定义图案就显示图案，否则用组内前 4 个地点的小图标拼成预览
struct FolderIconView: View {
    let group: PlaceGroup
    let members: [Place]
    var size: CGFloat = 60

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(Color(hex: group.colorHex).gradient)
            if !group.icon.isEmpty {
                if UIImage(systemName: group.icon) != nil {
                    Image(systemName: group.icon)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(group.icon).font(.system(size: size * 0.5))
                }
            } else {
                // 2×2 成员预览
                let mini = size * 0.32
                let gap = size * 0.08
                VStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<2, id: \.self) { col in
                                let i = row * 2 + col
                                if i < members.count {
                                    PlaceIconView(icon: members[i].icon, colorHex: members[i].colorHex, size: mini)
                                } else {
                                    Circle().fill(.white.opacity(0.25)).frame(width: mini, height: mini)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

/// 首页上的文件夹格子：图标 + 名称 + 地点数
struct FolderTile: View {
    @AppStorage("textSize") private var textSize: TextSize = .system
    let group: PlaceGroup
    let members: [Place]
    /// 有地点拖到上方时放大提示
    var targeted: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            FolderIconView(group: group, members: members, size: 60)
                .scaleEffect(targeted ? 1.18 : 1)
                .animation(.snappy, value: targeted)
            Text(group.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(members.count) 个地点")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .appTextSize(textSize)
    }
}

// MARK: - 分组编辑（名称 / 图案 / 颜色）

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Place.sortIndex) private var places: [Place]
    @Query private var groups: [PlaceGroup]

    /// nil 表示新建
    let group: PlaceGroup?
    /// 新建完成后回调（例如顺便把地点放进去）
    var onCreate: ((PlaceGroup) -> Void)? = nil

    @State private var name = ""
    @State private var icon = ""
    @State private var colorHex = "#007AFF"
    @State private var emojiInput = ""
    @State private var loaded = false
    @State private var preview = PlaceGroup(name: "")

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool { groups.contains { $0.name == trimmed && $0 !== group } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        FolderIconView(group: preview,
                                       members: group.map { g in places.filter { $0.groupName == g.name } } ?? [],
                                       size: 60)
                        TextField("分组名称，例如：客户", text: $name)
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if nameTaken { Text("已经有同名的分组了。").foregroundStyle(.red) }
                }

                Section {
                    Button {
                        icon = ""
                    } label: {
                        HStack {
                            Label("显示组内地点预览", systemImage: "square.grid.2x2")
                            Spacer()
                            if icon.isEmpty { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Presets.folderSymbols, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 18))
                                    .frame(width: 40, height: 40)
                                    .background(icon == symbol ? Color(hex: colorHex).opacity(0.25) : Color(.secondarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("或者输入一个 emoji 😀", text: $emojiInput)
                        .onChange(of: emojiInput) { _, newValue in
                            if let last = newValue.last {
                                icon = String(last)
                                if newValue.count > 1 { emojiInput = String(last) }
                            }
                        }
                } header: {
                    Text("图案")
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Presets.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let group {
                    Section {
                        Button("删除这个分组", role: .destructive) {
                            GroupStore.delete(group, places: places, in: context)
                            dismiss()
                        }
                    } footer: {
                        Text("删除分组不会删除里面的地点，它们会变成未分组。")
                    }
                }
            }
            .navigationTitle(group == nil ? "新建分组" : "编辑分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(trimmed.isEmpty || nameTaken)
                }
            }
            .onAppear(perform: load)
            .onChange(of: icon) { preview.icon = icon }
            .onChange(of: colorHex) { preview.colorHex = colorHex }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let group {
            name = group.name
            icon = group.icon
            colorHex = group.colorHex
        } else {
            colorHex = Presets.colors[(groups.count + 6) % Presets.colors.count]
        }
        preview.icon = icon
        preview.colorHex = colorHex
    }

    private func save() {
        if let group {
            GroupStore.rename(group, to: trimmed, places: places)
            group.icon = icon
            group.colorHex = colorHex
        } else if let created = GroupStore.ensure(trimmed, in: context) {
            created.icon = icon
            created.colorHex = colorHex
            onCreate?(created)
        }
        dismiss()
    }
}

// MARK: - 分组管理

struct GroupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Place.sortIndex) private var places: [Place]
    @Query(sort: \PlaceGroup.sortIndex) private var groups: [PlaceGroup]

    @State private var editing: PlaceGroup?
    @State private var showingNew = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedIDs) {
                Section {
                    ForEach(groups) { g in
                        NavigationLink {
                            GroupMembersView(group: g)
                        } label: {
                            HStack(spacing: 12) {
                                FolderIconView(group: g, members: places.filter { $0.groupName == g.name }, size: 36)
                                Text(g.name)
                                Spacer()
                                Text("\(places.filter { $0.groupName == g.name }.count) 个地点")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                GroupStore.delete(g, places: places, in: context)
                            } label: { Label("删除", systemImage: "trash") }
                            Button { editing = g } label: { Label("编辑", systemImage: "pencil") }
                                .tint(.orange)
                        }
                    }
                    .onMove { from, to in
                        var list = groups
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, g) in list.enumerated() where g.sortIndex != i { g.sortIndex = i }
                    }
                } footer: {
                    Text(groups.isEmpty
                         ? "还没有分组。点右上角「+」新建一个，再选择要放进去的地点。"
                         : "点分组选择里面的地点；左滑可以编辑（名称、图案、颜色）或删除；点「编辑」可以拖动调整顺序、多选批量删除。删除分组不会删除地点。")
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !groups.isEmpty {
                        Button(editMode.isEditing ? "好" : "编辑") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            selectedIDs.removeAll()
                        }
                    }
                    Button { showingNew = true } label: { Label("新建", systemImage: "plus") }
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Text(selectedIDs.isEmpty ? "选择要删除的分组" : "删除 \(selectedIDs.count) 个分组")
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingNew) { GroupEditorView(group: nil) }
            .sheet(item: $editing) { GroupEditorView(group: $0) }
            .confirmationDialog("删除 \(selectedIDs.count) 个分组？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除分组", role: .destructive) {
                    for g in groups where selectedIDs.contains(g.id) {
                        GroupStore.delete(g, places: places, in: context)
                    }
                    selectedIDs.removeAll()
                    editMode = .inactive
                }
            } message: {
                Text("里面的地点不会被删除，只会变成未分组。")
            }
        }
    }
}

/// 勾选某个分组包含哪些地点（一个地点只能在一个分组里）
struct GroupMembersView: View {
    let group: PlaceGroup
    @Query(sort: \Place.sortIndex) private var places: [Place]

    var body: some View {
        List {
            Section {
                ForEach(places) { place in
                    Button {
                        place.groupName = (place.groupName == group.name) ? "" : group.name
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: place.groupName == group.name ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(place.groupName == group.name ? Color.accentColor : Color.secondary)
                            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                if !place.groupName.isEmpty && place.groupName != group.name {
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
                Text("勾选的地点会放进「\(group.name)」。已经在其他分组里的地点会移过来。")
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("全选") { for p in places { p.groupName = group.name } }
                    Button("只选未分组的") { for p in places where p.groupName.isEmpty { p.groupName = group.name } }
                    Button("全部取消", role: .destructive) {
                        for p in places where p.groupName == group.name { p.groupName = "" }
                    }
                } label: {
                    Image(systemName: "checklist")
                }
            }
        }
    }
}
