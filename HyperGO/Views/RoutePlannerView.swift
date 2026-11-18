import SwiftUI
import SwiftData
import MapKit

/// Google 地图 URL 最多支持约 9 个途经点 + 1 个终点
private let maxStops = 10

struct RoutePlannerView: View {
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex) private var places: [Place]

    @State private var selection = Set<PersistentIdentifier>()
    @AppStorage("route.fromCurrent") private var fromCurrentLocation = true
    @AppStorage("route.returnToStart") private var returnToStart = false
    @State private var plan: RoutePlan?
    @AppStorage("groupFilter") private var groupFilter = PlaceGroups.all

    private var visible: [Place] { PlaceGroups.filter(places, by: groupFilter) }

    private var selectedPlaces: [Place] { places.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                if !PlaceGroups.names(in: places).isEmpty {
                    Section {
                        GroupFilterBar(places: places, selection: $groupFilter)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    Toggle("从当前位置出发", isOn: $fromCurrentLocation)
                    Toggle("最后回到出发点", isOn: $returnToStart)
                        .disabled(!fromCurrentLocation)
                } footer: {
                    if fromCurrentLocation && locationManager.location == nil {
                        Text("尚未获取到当前位置，请在系统设置中允许定位。")
                    }
                }

                Section {
                    ForEach(visible) { place in
                        Button { toggle(place) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(place.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(place.id) ? Color.accentColor : Color.secondary)
                                PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 32)
                                Text(place.name)
                                Spacer()
                                if let d = locationManager.distance(to: place.coordinate) {
                                    Text(Format.distance(d)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("选择要去的地点（\(selection.count)/\(maxStops)）")
                        Spacer()
                        if selection.count < maxStops && visible.contains(where: { !selection.contains($0.id) }) {
                            Button("全选") { selectAllVisible() }.font(.caption)
                        }
                        if !selection.isEmpty {
                            Button("清空") { selection.removeAll() }.font(.caption)
                        }
                    }
                }
            }
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView("还没有地点", systemImage: "mappin.slash",
                                           description: Text("先在「地点」页添加几个地点。"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: compute) {
                    Label("计算最短路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCompute)
                .padding()
                .background(.bar)
            }
            .navigationTitle("路线规划")
            .sheet(item: $plan) { RouteResultView(plan: $0) }
        }
    }

    private var canCompute: Bool {
        let needed = fromCurrentLocation ? 1 : 2
        if fromCurrentLocation && locationManager.location == nil { return false }
        return selection.count >= needed
    }

    /// 选中当前分组里的地点，最多到 maxStops 个
    private func selectAllVisible() {
        for p in visible where selection.count < maxStops { selection.insert(p.id) }
    }

    private func toggle(_ place: Place) {
        if selection.contains(place.id) {
            selection.remove(place.id)
        } else if selection.count < maxStops {
            selection.insert(place.id)
        }
    }

    private func compute() {
        let stops = selectedPlaces
        let start = fromCurrentLocation ? locationManager.location?.coordinate : nil
        let ret = fromCurrentLocation && returnToStart
        let result = RouteOptimizer.optimize(points: stops.map(\.coordinate), start: start, returnToStart: ret)
        plan = RoutePlan(stops: result.order.map { stops[$0] }, start: start,
                         returnToStart: ret, straightMeters: result.totalMeters)
    }
}

struct RoutePlan: Identifiable {
    let id = UUID()
    let stops: [Place]
    let start: CLLocationCoordinate2D?
    let returnToStart: Bool
    let straightMeters: Double

    /// 依次经过的所有坐标（含起点/返回点）
    var path: [CLLocationCoordinate2D] {
        var coords = stops.map(\.coordinate)
        if let start {
            coords.insert(start, at: 0)
            if returnToStart { coords.append(start) }
        }
        return coords
    }
}

struct RouteResultView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving
    let plan: RoutePlan

    @State private var roads: [MKRoute] = []
    @State private var loadingRoads = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(initialPosition: .automatic) {
                        if roads.count == plan.path.count - 1 {
                            ForEach(roads.indices, id: \.self) { i in
                                MapPolyline(roads[i]).stroke(.blue, lineWidth: 5)
                            }
                        } else {
                            MapPolyline(coordinates: plan.path).stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                        }
                        if let start = plan.start {
                            Annotation("出发", coordinate: start) {
                                Circle().fill(.green).frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                        ForEach(Array(plan.stops.enumerated()), id: \.offset) { i, place in
                            Annotation(place.name, coordinate: place.coordinate) {
                                Text("\(i + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color(hex: place.colorHex), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent("直线总距离", value: Format.distance(plan.straightMeters))
                    if loadingRoads {
                        LabeledContent("道路距离") { ProgressView() }
                    } else if roads.count == plan.path.count - 1 {
                        LabeledContent("道路距离", value: Format.distance(roads.reduce(0) { $0 + $1.distance }))
                        LabeledContent("预计用时", value: Format.duration(roads.reduce(0) { $0 + $1.expectedTravelTime }))
                    }
                } footer: {
                    Text("访问顺序按直线距离优化；道路距离和用时由 Apple 地图估算，仅供参考。")
                }

                Section("访问顺序") {
                    if plan.start != nil {
                        Label("当前位置", systemImage: "location.circle.fill").foregroundStyle(.green)
                    }
                    ForEach(Array(plan.stops.enumerated()), id: \.offset) { i, place in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.headline).monospacedDigit().frame(width: 24)
                            PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 30)
                            Text(place.name)
                            Spacer()
                            if let leg = legText(i) {
                                Text(leg).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    if plan.returnToStart {
                        Label("回到出发点", systemImage: "arrow.uturn.backward.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let stops = plan.stops.map(\.coordinate) + (plan.returnToStart ? [plan.start!] : [])
                    let origin = plan.start == nil ? stops.first : nil
                    let rest = plan.start == nil ? Array(stops.dropFirst()) : stops
                    GoogleMaps.route(origin: origin, stops: rest, mode: travelMode)
                } label: {
                    Label("用 Google 地图开始导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .navigationTitle("最短路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await loadRoads() }
        }
    }

    /// 第 i 站与上一站之间的距离
    private func legText(_ i: Int) -> String? {
        let legIndex = plan.start == nil ? i - 1 : i
        guard legIndex >= 0 else { return nil }
        if roads.count == plan.path.count - 1 {
            return Format.distance(roads[legIndex].distance)
        }
        let a = plan.path[legIndex], b = plan.path[legIndex + 1]
        return Format.distance(CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
    }

    /// 逐段向 Apple 地图请求道路路线，用于在地图上画出真实路径
    private func loadRoads() async {
        defer { loadingRoads = false }
        let type = travelMode.mkTransportType
        let path = plan.path
        var result: [MKRoute] = []
        for i in 0..<(path.count - 1) {
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: path[i]))
            req.destination = MKMapItem(placemark: MKPlacemark(coordinate: path[i + 1]))
            req.transportType = type
            guard let route = try? await MKDirections(request: req).calculate().routes.first else { return }
            result.append(route)
        }
        roads = result
    }
}
