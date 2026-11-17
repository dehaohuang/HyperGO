import SwiftUI
import MapKit

/// 在地图上点选位置，或搜索地址
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager

    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var address: String
    @Binding var suggestedName: String
    var initial: CLLocationCoordinate2D?

    @State private var picked: CLLocationCoordinate2D?
    @State private var pickedAddress = ""
    @State private var pickedName = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var geocodeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if let picked {
                        Marker(pickedName.isEmpty ? "选中的位置" : pickedName, coordinate: picked)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange { context in visibleRegion = context.region }
                .onTapGesture { point in
                    if let c = proxy.convert(point, from: .local) {
                        select(c, name: "", address: nil)
                    }
                }
            }
            .overlay(alignment: .top) {
                if !results.isEmpty {
                    List(results, id: \.self) { item in
                        Button {
                            select(item.placemark.coordinate, name: item.name ?? "", address: item.placemark.title)
                            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                                                                latitudinalMeters: 1000, longitudinalMeters: 1000))
                            results = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "未知地点").foregroundStyle(.primary)
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 6)
                    .padding(.horizontal)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索地点或地址")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, newValue in if newValue.isEmpty { results = [] } }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear {
                if let initial {
                    picked = initial
                    camera = .region(MKCoordinateRegion(center: initial, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if picked != nil {
                if !pickedName.isEmpty { Text(pickedName).font(.headline) }
                Text(pickedAddress.isEmpty ? "正在获取地址…" : pickedAddress)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("点地图选择位置，或在上方搜索").foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    if let loc = locationManager.location?.coordinate {
                        select(loc, name: "", address: nil)
                        camera = .userLocation(fallback: .automatic)
                    }
                } label: {
                    Label("当前位置", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
                .disabled(locationManager.location == nil)

                Spacer()

                Button("使用这个位置") {
                    coordinate = picked
                    address = pickedAddress
                    if !pickedName.isEmpty { suggestedName = pickedName }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked == nil)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func select(_ c: CLLocationCoordinate2D, name: String, address: String?) {
        picked = c
        pickedName = name
        pickedAddress = address ?? ""
        geocodeTask?.cancel()
        guard address == nil else { return }
        geocodeTask = Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            guard !Task.isCancelled else { return }
            pickedAddress = placemark.map(Self.format) ?? String(format: "%.5f, %.5f", c.latitude, c.longitude)
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let visibleRegion { request.region = visibleRegion }
        let response = try? await MKLocalSearch(request: request).start()
        results = response?.mapItems ?? []
    }

    static func format(_ p: CLPlacemark) -> String {
        let parts = [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare, p.name]
            .compactMap { $0 }
        // 去掉重复片段（name 常包含街道）
        var result: [String] = []
        for part in parts where !result.contains(where: { $0.contains(part) || part.contains($0) }) {
            result.append(part)
        }
        return result.joined(separator: " ")
    }
}
