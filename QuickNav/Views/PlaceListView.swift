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

    var body: some View {
        NavigationStack {
            List {
                ForEach(places) { place in
                    Button {
                        GoogleMaps.navigate(to: place.coordinate, mode: travelMode)
                    } label: {
                        PlaceRow(place: place, distance: locationManager.distance(to: place.coordinate))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(place) } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button { editingPlace = place } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button { editingPlace = place } label: { Label("编辑", systemImage: "pencil") }
                        Button(role: .destructive) { delete(place) } label: { Label("删除", systemImage: "trash") }
                    }
                }
                .onMove(perform: move)
            }
            .listStyle(.insetGrouped)
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
            .navigationTitle("快捷导航")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label(travelMode.title, systemImage: travelMode.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !places.isEmpty { EditButton() }
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

    private func move(from source: IndexSet, to destination: Int) {
        var items = places
        items.move(fromOffsets: source, toOffset: destination)
        for (i, item) in items.enumerated() { item.sortIndex = i }
    }
}

struct PlaceRow: View {
    let place: Place
    let distance: Double?

    var body: some View {
        HStack(spacing: 14) {
            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(.headline)
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                if let distance {
                    Text(Format.distance(distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving

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
