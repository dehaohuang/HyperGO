import SwiftUI
import SwiftData
import MapKit

struct PlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// nil 表示新建
    let place: Place?
    /// 新建时可预设位置（例如从地图页添加）
    var initialCoordinate: CLLocationCoordinate2D? = nil
    /// 新建时预设分组（例如在文件夹里添加）
    var initialGroup: String = ""

    @State private var name = ""
    @State private var icon = "mappin"
    @State private var colorHex = Presets.colors[0]
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var suggestedName = ""
    @State private var emojiInput = ""
    @State private var showingPicker = false
    @State private var loaded = false
    @State private var groupName = ""
    @Query(sort: \PlaceGroup.sortIndex) private var allGroups: [PlaceGroup]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && coordinate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PlaceIconView(icon: icon, colorHex: colorHex, size: 56)
                        TextField("名称，例如：家、公司", text: $name)
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                }

                Section("位置") {
                    if let coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                            Annotation("", coordinate: coordinate) {
                                PlaceIconView(icon: icon, colorHex: colorHex, size: 30)
                            }
                        }
                        .id("\(coordinate.latitude),\(coordinate.longitude)")
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        if !address.isEmpty {
                            Text(address).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        Label(coordinate == nil ? "选择位置" : "重新选择位置", systemImage: "mappin.and.ellipse")
                    }
                }

                Section {
                    TextField("不分组", text: $groupName)
                    let groups = allGroups.map(\.name)
                    if !groups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(groups, id: \.self) { g in
                                    GroupChip(title: g, selected: groupName == g) {
                                        groupName = (groupName == g) ? "" : g
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("分组")
                } footer: {
                    Text("输入新的分组名称，或点下面已有的分组。留空就是不分组。")
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Presets.symbols, id: \.self) { symbol in
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

                if let place {
                    Section {
                        Button("删除这个地点", role: .destructive) {
                            context.delete(place)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(place == nil ? "添加地点" : "编辑地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                LocationPickerView(coordinate: $coordinate, address: $address, suggestedName: $suggestedName,
                                   initial: coordinate)
            }
            .onChange(of: suggestedName) { _, newValue in
                if name.isEmpty { name = newValue }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let place {
            name = place.name
            icon = place.icon
            colorHex = place.colorHex
            coordinate = place.coordinate
            address = place.address
            groupName = place.groupName
        } else {
            groupName = initialGroup
            if let initialCoordinate { coordinate = initialCoordinate }
        }
    }

    private func save() {
        guard let coordinate else { return }
        GroupStore.ensure(groupName, in: context)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let place {
            place.name = trimmed
            place.icon = icon
            place.colorHex = colorHex
            place.latitude = coordinate.latitude
            place.longitude = coordinate.longitude
            place.address = address
            let newGroup = groupName.trimmingCharacters(in: .whitespaces)
            if place.groupName != newGroup {
                place.groupName = newGroup
                place.sortIndex = GroupStore.nextSortIndex(in: context)
            }
        } else {
            let count = GroupStore.nextSortIndex(in: context)
            context.insert(Place(name: trimmed, icon: icon, colorHex: colorHex,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude,
                                 address: address, sortIndex: count,
                                 groupName: groupName.trimmingCharacters(in: .whitespaces)))
        }
        dismiss()
    }
}
