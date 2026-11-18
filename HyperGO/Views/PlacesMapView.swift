import SwiftUI
import SwiftData
import MapKit

struct PlacesMapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \Place.sortIndex) private var places: [Place]
    @AppStorage("travelMode") private var travelMode: TravelMode = .driving

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: Place?
    @State private var eta: (seconds: TimeInterval, meters: Double)?
    @State private var center: CLLocationCoordinate2D?
    /// 显示名称的地点：按屏幕位置做避让，会重叠的名称先隐藏，放大后再出现
    @State private var labeled = Set<PersistentIdentifier>()
    @State private var addingAt: AddRequest?
    /// 隐藏地图自带的兴趣点名称（商店、餐厅等），只留自己的地点
    @AppStorage("hideMapLabels") private var hideMapLabels = false
    /// 地图页自己的分组筛选（可多选，和路线页互不影响）；空 = 全部
    @AppStorage("map.groupFilter") private var groupFilterRaw = ""
    @Query(sort: \PlaceGroup.sortIndex) private var groups: [PlaceGroup]
    private var groupFilter: Binding<Set<String>> {
        Binding(get: { PlaceGroups.decode(groupFilterRaw) }, set: { groupFilterRaw = PlaceGroups.encode($0) })
    }
    @AppStorage("textSize") private var textSize: TextSize = .system

    private var visible: [Place] { PlaceGroups.filter(places, by: PlaceGroups.decode(groupFilterRaw)) }

    struct AddRequest: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
          MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                ForEach(visible) { place in
                    // 名称自己画在图标下方，这样才能跟随设置里的字体大小
                    Annotation("", coordinate: place.coordinate) {
                        PlaceIconView(icon: place.icon, colorHex: place.colorHex,
                                      size: selected?.id == place.id ? 42 : 32)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                            .overlay(alignment: .top) {
                                if labeled.contains(place.id) || selected?.id == place.id {
                                    MapPlaceLabel(name: place.name)
                                        .appTextSize(textSize)
                                        .fixedSize()
                                        .offset(y: (selected?.id == place.id ? 42 : 32) + 3)
                                }
                            }
                            .onTapGesture { select(place) }
                            .animation(.snappy, value: selected?.id)
                    }
                }
            }
            .mapStyle(hideMapLabels
                      ? .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
                      : .standard)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange { context in
                center = context.region.center
                updateLabels(proxy)
            }
            .onChange(of: visible.map(\.id)) { updateLabels(proxy) }
            .onChange(of: textSize) { updateLabels(proxy) }
            .onChange(of: selected?.id) { updateLabels(proxy) }
          }
            .overlay(alignment: .center) {
                if selected == nil {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .top) {
                MultiGroupFilterBar(places: places, groups: groups, selection: groupFilter)
                    .background(.ultraThinMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                if let selected { card(for: selected) }
            }
            .onChange(of: groupFilterRaw) {
                // 切换分组后取消选中，并缩放到能看到这一组的所有地点
                if let s = selected, !visible.contains(s) { selected = nil }
                withAnimation { camera = .automatic }
            }
            .navigationTitle("地图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("全部") {
                        selected = nil
                        withAnimation { camera = .automatic }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { hideMapLabels.toggle() }
                    } label: {
                        Label(hideMapLabels ? "显示地图文字" : "隐藏地图文字",
                              systemImage: hideMapLabels ? "eye.slash" : "eye")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let center { addingAt = AddRequest(coordinate: center) }
                    } label: {
                        Label("在中心添加", systemImage: "plus.circle")
                    }
                }
            }
            .sheet(item: $addingAt) { req in
                PlaceEditorView(place: nil, initialCoordinate: req.coordinate)
            }
        }
    }

    /// 按屏幕坐标逐个放置名称；和已放置的名称或其他图标重叠就不显示
    private func updateLabels(_ proxy: MapProxy) {
        let font = MapPlaceLabel.uiFont(for: textSize)
        let iconRects: [CGRect] = visible.compactMap { p in
            guard let pt = proxy.convert(p.coordinate, to: .local) else { return nil }
            let s: CGFloat = selected?.id == p.id ? 42 : 32
            return CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)
        }
        // 选中的地点优先，其余按首页顺序
        let ordered = visible.sorted { a, b in
            (a.id == selected?.id ? 0 : 1, a.sortIndex) < (b.id == selected?.id ? 0 : 1, b.sortIndex)
        }
        var placed: [CGRect] = []
        var result = Set<PersistentIdentifier>()
        for p in ordered {
            guard let pt = proxy.convert(p.coordinate, to: .local) else { continue }
            let s: CGFloat = selected?.id == p.id ? 42 : 32
            let text = (p.name as NSString).size(withAttributes: [.font: font])
            let w = ceil(text.width) + 10, h = ceil(text.height) + 2
            let rect = CGRect(x: pt.x - w / 2, y: pt.y + s / 2 + 3, width: w, height: h)
            let ownIcon = CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)
            let hitsLabel = placed.contains { $0.insetBy(dx: -2, dy: -1).intersects(rect) }
            let hitsIcon = iconRects.contains { $0 != ownIcon && $0.intersects(rect) }
            if !hitsLabel && !hitsIcon {
                placed.append(rect)
                result.insert(p.id)
            }
        }
        if result != labeled { labeled = result }
    }

    private func select(_ place: Place) {
        selected = place
        eta = nil
        Task { await loadETA(for: place) }
    }

    @ViewBuilder
    private func card(for place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlaceIconView(icon: place.icon, colorHex: place.colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    if !place.address.isEmpty {
                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                if let d = locationManager.distance(to: place.coordinate) {
                    Label("直线 \(Format.distance(d))", systemImage: "ruler")
                }
                if let eta {
                    Label("\(travelMode.title) \(Format.duration(eta.seconds)) · \(Format.distance(eta.meters))",
                          systemImage: travelMode.symbol)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button {
                GoogleMaps.navigate(to: place.coordinate, mode: travelMode)
            } label: {
                Label("用 Google 地图导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func loadETA(for place: Place) async {
        guard locationManager.location != nil else { return }
        let type = travelMode.mkTransportType
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        request.transportType = type
        guard let response = try? await MKDirections(request: request).calculateETA(),
              selected?.id == place.id else { return }
        eta = (response.expectedTravelTime, response.distance)
    }
}

/// 地图上地点图标下方的名称：白色描边，任何底图上都看得清
struct MapPlaceLabel: View {
    let name: String

    /// 与 Text 实际显示一致的字体（用于计算名称占多大地方）
    static func uiFont(for size: TextSize) -> UIFont {
        let category: UIContentSizeCategory = switch size {
        case .system: UIApplication.shared.preferredContentSizeCategory
        case .small: .small
        case .standard: .large
        case .large: .extraLarge
        case .xLarge: .extraExtraLarge
        case .xxLarge: .extraExtraExtraLarge
        }
        let base = UIFont.preferredFont(forTextStyle: .caption1,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        return UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
    }

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.background.opacity(0.75), in: Capsule())
            .allowsHitTesting(false)
    }
}
