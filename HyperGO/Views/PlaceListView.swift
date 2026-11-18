import SwiftUI
import SwiftData

struct PlaceListView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex) private var places: [Place]
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving

    @State private var editingPlace: Place?
    @State private var showingNew = false
    @State private var showingSettings = false

    /// 一排最多 4 个图标
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                        Button {
                            GoogleMaps.navigate(to: place.coordinate, mode: travelMode)
                        } label: {
                            PlaceTile(place: place, distance: locationManager.distance(to: place.coordinate))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editingPlace = place } label: { Label("编辑", systemImage: "pencil") }
                            Button(role: .destructive) { delete(place) } label: { Label("删除", systemImage: "trash") }
                        }
                        .draggable(String(index)) {
                            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 60)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let from = items.first.flatMap(Int.init), from != index else { return false }
                            withAnimation { move(from: from, to: index) }
                            return true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .overlay {
                if places.isEmpty {
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
            .navigationTitle("HyperGO")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label(travelMode.title, systemImage: travelMode.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) { PlaceEditorView(place: nil) }
            .sheet(item: $editingPlace) { PlaceEditorView(place: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private func delete(_ place: Place) {
        context.delete(place)
    }

    /// 拖动图标调整顺序：把 from 位置的地点移到 to 位置
    private func move(from: Int, to: Int) {
        guard places.indices.contains(from), places.indices.contains(to) else { return }
        var items = places
        let item = items.remove(at: from)
        items.insert(item, at: to)
        for (i, item) in items.enumerated() { item.sortIndex = i }
    }
}

/// 主屏幕风格的图标：彩色圆形图标 + 名称 + 距离
struct PlaceTile: View {
    let place: Place
    let distance: Double?

    var body: some View {
        VStack(spacing: 6) {
            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 60)
            Text(place.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let distance {
                Text(Format.distance(distance))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving
    @AppStorage("textSize") private var textSize: TextSize = .system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("出行方式", selection: $travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("出行方式")
                } footer: {
                    Text("打开 Google 地图时使用的默认出行方式。")
                }
                Section {
                    Picker("字体大小", selection: $textSize) {
                        ForEach(TextSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                } header: {
                    Text("字体大小")
                } footer: {
                    Text("调整整个 App 的文字大小。「跟随系统」使用 iPhone 设置 → 显示与亮度 → 文字大小。")
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
