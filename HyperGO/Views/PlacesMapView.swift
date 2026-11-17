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
    @State private var addingAt: AddRequest?

    struct AddRequest: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(places) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        PlaceIconView(icon: place.icon, colorHex: place.colorHex,
                                      size: selected?.id == place.id ? 42 : 32)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                            .onTapGesture { select(place) }
                            .animation(.snappy, value: selected?.id)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange { context in center = context.region.center }
            .overlay(alignment: .center) {
                if selected == nil {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected { card(for: selected) }
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
        guard let type = travelMode.mkTransportType, locationManager.location != nil else { return }
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        request.transportType = type
        guard let response = try? await MKDirections(request: request).calculateETA(),
              selected?.id == place.id else { return }
        eta = (response.expectedTravelTime, response.distance)
    }
}
