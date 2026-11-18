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
    @State private var showingImport = false
    @State private var routeDistances = RouteDistanceStore()

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
                            PlaceTile(place: place,
                                      routeDistance: routeDistances.distance(to: place.coordinate),
                                      straightDistance: locationManager.distance(to: place.coordinate))
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
            .task(id: distanceRefreshKey) {
                routeDistances.refresh(from: locationManager.location,
                                       to: places.map(\.coordinate),
                                       mode: travelMode)
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
                        Label("设置", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingNew = true } label: { Label("添加地点", systemImage: "mappin.and.ellipse") }
                        Button { showingImport = true } label: { Label("批量导入", systemImage: "square.and.arrow.down.on.square") }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        showingNew = true
                    }
                }
            }
            .sheet(isPresented: $showingNew) { PlaceEditorView(place: nil) }
            .sheet(item: $editingPlace) { PlaceEditorView(place: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingImport) { ImportPlacesView() }
        }
    }

    private func delete(_ place: Place) {
        context.delete(place)
    }

    /// 位置（约 100 米精度）、出行方式或地点变化时重新计算道路距离
    private var distanceRefreshKey: String {
        let loc = locationManager.location.map {
            String(format: "%.3f,%.3f", $0.coordinate.latitude, $0.coordinate.longitude)
        } ?? "none"
        let dests = places.map { RouteDistanceStore.key($0.coordinate) }.joined(separator: ";")
        return "\(loc)|\(travelMode.rawValue)|\(dests)"
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
    /// 最短实际道路距离（还没算好时为 nil）
    let routeDistance: Double?
    /// 直线距离，道路距离算好前先用「≈」显示
    let straightDistance: Double?

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
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
