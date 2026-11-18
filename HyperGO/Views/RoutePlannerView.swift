import SwiftUI
import SwiftData
import MapKit

struct RoutePlannerView: View {
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex) private var places: [Place]

    @State private var selection = Set<PersistentIdentifier>()
    @AppStorage("route.fromCurrent") private var fromCurrentLocation = true
    @AppStorage("route.returnToStart") private var returnToStart = false
    @State private var plan: RoutePlan?
    @State private var computing = false
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
                        Text("选择要去的地点（已选 \(selection.count) 个）")
                        Spacer()
                        if visible.contains(where: { !selection.contains($0.id) }) {
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
                Button { Task { await compute() } } label: {
                    if computing {
                        HStack(spacing: 8) { ProgressView(); Text("正在计算最短顺序…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(selection.count > GoogleMaps.maxStopsPerRoute
                              ? "计算最短路线（\(selection.count) 个地点，自动分段）"
                              : "计算最短路线",
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCompute || computing)
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

    /// 选中当前分组里的全部地点
    private func selectAllVisible() {
        for p in visible { selection.insert(p.id) }
    }

    private func toggle(_ place: Place) {
        if selection.contains(place.id) {
            selection.remove(place.id)
        } else {
            selection.insert(place.id)
        }
    }

    /// 在后台计算，地点很多时界面也不会卡
    private func compute() async {
        let stops = selectedPlaces
        let coords = stops.map(\.coordinate)
        let start = fromCurrentLocation ? locationManager.location?.coordinate : nil
        let ret = fromCurrentLocation && returnToStart
        computing = true
        let result = await Task.detached(priority: .userInitiated) {
            RouteOptimizer.optimize(points: coords, start: start, returnToStart: ret)
        }.value
        computing = false
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

    /// 一段 Google 地图导航：origin 为 nil 表示从当前位置出发
    struct Segment: Identifiable {
        let id: Int
        let origin: CLLocationCoordinate2D?
        let stops: [CLLocationCoordinate2D]
        /// 本段在访问顺序里的站号范围（从 1 开始；「回到出发点」记为最后一站之后）
        let firstNumber: Int
        let lastNumber: Int
    }

    /// 按 Google 地图的上限切成几段；第 2 段起从当时所在位置（上一段终点）出发
    var segments: [Segment] {
        var destinations = stops.map(\.coordinate)
        var origin: CLLocationCoordinate2D? = nil
        var number = 1
        if start == nil, let first = destinations.first {
            origin = first
            destinations.removeFirst()
            number = 2
        }
        if returnToStart, let start { destinations.append(start) }
        var result: [Segment] = []
        var i = 0
        while i < destinations.count {
            let chunk = Array(destinations[i..<min(i + GoogleMaps.maxStopsPerRoute, destinations.count)])
            result.append(Segment(id: result.count, origin: result.isEmpty ? origin : nil, stops: chunk,
                                  firstNumber: number, lastNumber: number + chunk.count - 1))
            number += chunk.count
            i += chunk.count
        }
        return result
    }

    /// 第 n 站（从 1 开始）的名称；超出地点数时是「出发点」
    func stopName(_ number: Int) -> String {
        number >= 1 && number <= stops.count ? stops[number - 1].name : "出发点"
    }

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

    /// 每一段路（相邻两站之间）的道路路线；算不出来的为 nil
    @State private var roads: [MKRoute?] = []
    @State private var loadingRoads = true
    /// 已经点过「导航」的分段
    @State private var startedSegments = Set<Int>()

    private var legCount: Int { plan.path.count - 1 }
    private var loadedRoads: [MKRoute] { roads.compactMap { $0 } }
    private var allRoadsLoaded: Bool { roads.count == legCount && loadedRoads.count == legCount }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(initialPosition: .automatic) {
                        // 已算出的路段画实线，还没算出来的画虚直线
                        ForEach(0..<legCount, id: \.self) { i in
                            if i < roads.count, let road = roads[i] {
                                MapPolyline(road).stroke(.blue, lineWidth: 5)
                            } else {
                                MapPolyline(coordinates: [plan.path[i], plan.path[i + 1]])
                                    .stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                            }
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
                    LabeledContent("地点数", value: "\(plan.stops.count) 个")
                    LabeledContent("直线总距离", value: Format.distance(plan.straightMeters))
                    if loadingRoads {
                        LabeledContent("道路距离") {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("\(roads.count)/\(legCount)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    } else if !loadedRoads.isEmpty {
                        LabeledContent(allRoadsLoaded ? "道路总距离" : "道路距离（部分）",
                                       value: Format.distance(loadedRoads.reduce(0) { $0 + $1.distance }))
                        LabeledContent(allRoadsLoaded ? "预计总用时" : "预计用时（部分）",
                                       value: Format.duration(loadedRoads.reduce(0) { $0 + $1.expectedTravelTime }))
                    }
                } footer: {
                    Text(plan.stops.count > 12
                         ? "地点较多，访问顺序按直线距离用近似算法优化（接近最优）；道路距离和用时由 Apple 地图估算，仅供参考。"
                         : "访问顺序按直线距离计算出最优解；道路距离和用时由 Apple 地图估算，仅供参考。")
                }

                if plan.segments.count > 1 {
                    Section {
                        ForEach(plan.segments) { seg in
                            HStack(spacing: 12) {
                                Image(systemName: startedSegments.contains(seg.id) ? "checkmark.circle.fill" : "\(seg.id + 1).circle")
                                    .font(.title2)
                                    .foregroundStyle(startedSegments.contains(seg.id) ? Color.green : Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("第 \(seg.id + 1) 段：第 \(seg.firstNumber)–\(seg.lastNumber) 站")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(plan.stopName(seg.firstNumber)) → \(plan.stopName(seg.lastNumber))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("导航") { open(seg) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } header: {
                        Text("分段导航（共 \(plan.segments.count) 段）")
                    } footer: {
                        Text("Google 地图一次最多导航 \(GoogleMaps.maxStopsPerRoute) 站，所以自动分成几段。跑完一段，回到这里点下一段，会从你当时的位置接着走。")
                    }
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
                    if let next = nextSegment { open(next) }
                } label: {
                    Label(bottomButtonTitle, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(nextSegment == nil)
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

    /// 下一段要导航的（第一个还没点过的；都点过就是最后一段）
    private var nextSegment: RoutePlan.Segment? {
        plan.segments.first { !startedSegments.contains($0.id) } ?? plan.segments.last
    }

    private var bottomButtonTitle: String {
        guard plan.segments.count > 1, let next = nextSegment else { return "用 Google 地图开始导航" }
        return "导航第 \(next.id + 1) 段（共 \(plan.segments.count) 段）"
    }

    private func open(_ seg: RoutePlan.Segment) {
        startedSegments.insert(seg.id)
        GoogleMaps.route(origin: seg.origin, stops: seg.stops, mode: travelMode)
    }

    /// 第 i 站与上一站之间的距离
    private func legText(_ i: Int) -> String? {
        let legIndex = plan.start == nil ? i - 1 : i
        guard legIndex >= 0 else { return nil }
        if legIndex < roads.count, let road = roads[legIndex] {
            return Format.distance(road.distance)
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
        roads = []
        for i in 0..<(path.count - 1) {
            if Task.isCancelled { return }
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: path[i]))
            req.destination = MKMapItem(placemark: MKPlacemark(coordinate: path[i + 1]))
            req.transportType = type
            var route = try? await MKDirections(request: req).calculate().routes.first
            if route == nil {
                // 可能是请求太快被限流，稍等再试一次
                try? await Task.sleep(for: .seconds(2))
                route = try? await MKDirections(request: req).calculate().routes.first
            }
            roads.append(route)
        }
    }
}
