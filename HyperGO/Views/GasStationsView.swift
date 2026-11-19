import SwiftUI
import MapKit

/// 加油站页：附近加油站地图 + 油价 + 性价比推荐
struct GasStationsView: View {
    @Environment(LocationManager.self) private var locationManager
    @AppStorage("navApp") private var navApp = NavApp.google.rawValue
    @AppStorage("fuel.type") private var fuelType: FuelType = .regular
    @AppStorage("fuel.radiusKm") private var radiusKm = 10.0
    @AppStorage("fuel.fillLitres") private var fillLitres = 40.0
    @AppStorage("fuel.consumption") private var consumption = 10.0
    @AppStorage(GasStationService.keyDefaultsKey) private var apiKey = ""

    @State private var service = GasStationService.shared
    @State private var distances = RouteDistanceStore()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: String?
    @State private var showSettings = false

    // MARK: - 计算

    /// 道路距离（还没算好时用直线距离 × 1.3 估算）
    private func distance(_ s: GasStation) -> Double? {
        if let d = distances.distance(to: s.coordinate) { return d }
        return locationManager.distance(to: s.coordinate).map { $0 * 1.3 }
    }

    private func price(_ s: GasStation) -> FuelPrice? { s.prices[fuelType] }

    /// 加满 fillLitres 升的总花费 + 来回路上的油费
    private func totalCost(_ s: GasStation) -> Double? {
        guard let p = price(s), let d = distance(s) else { return nil }
        let tripLitres = d * 2 / 1000 * consumption / 100
        return p.perLitre * (fillLitres + tripLitres)
    }

    private var sorted: [GasStation] {
        service.stations.sorted { (distance($0) ?? .infinity) < (distance($1) ?? .infinity) }
    }

    private var nearest: GasStation? { sorted.first }
    private var nearestPriced: GasStation? { sorted.first { price($0) != nil } }

    private var best: GasStation? {
        service.stations.filter { totalCost($0) != nil }.min { totalCost($0)! < totalCost($1)! }
    }

    private var cheapestPrice: Double? {
        service.stations.compactMap { price($0)?.perLitre }.min()
    }

    // MARK: - 页面

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                    .frame(maxHeight: .infinity)
                list
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle("加油站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("油品", selection: $fuelType) {
                            ForEach(FuelType.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label(fuelType.title, systemImage: "fuelpump")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await load(force: true) } } label: {
                        if service.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(service.loading)
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { GasSettingsView() }
            .task { await load(force: false) }
            .onChange(of: locationManager.location == nil) { Task { await load(force: false) } }
            .onChange(of: radiusKm) { Task { await load(force: false) } }
            .onChange(of: apiKey) { Task { await load(force: false) } }
            .onChange(of: service.stations.map(\.id)) { updateDistances(); fitMap() }
        }
    }

    private func load(force: Bool) async {
        await service.refresh(near: locationManager.location, radius: radiusKm * 1000, force: force)
        updateDistances()
    }

    /// 地图缩放到能看到附近的加油站（最多看最近的 8 家）
    private func fitMap() {
        guard let me = locationManager.location?.coordinate else { return }
        let pts = sorted.prefix(8).map(\.coordinate) + [me]
        let lats = pts.map(\.latitude), lons = pts.map(\.longitude)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.01),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.01))
        let center = CLLocationCoordinate2D(latitude: (lats.max()! + lats.min()!) / 2,
                                            longitude: (lons.max()! + lons.min()!) / 2)
        withAnimation { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    private func updateDistances() {
        distances.refresh(from: locationManager.location, to: sorted.map(\.coordinate), mode: .driving)
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(service.stations) { s in
                Annotation("", coordinate: s.coordinate) {
                    StationPin(price: price(s).map(FuelFormat.price),
                               isBest: s.id == best?.id,
                               isSelected: s.id == selectedID)
                        .onTapGesture { withAnimation(.snappy) { selectedID = s.id } }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .bottom) {
            if let s = service.stations.first(where: { $0.id == selectedID }) {
                stationCard(s)
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func stationCard(_ s: GasStation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.headline).lineLimit(1)
                Text(detailLine(s)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { Navigator.navigate(to: s.coordinate) } label: {
                Label("导航", systemImage: "location.fill")
            }
            .buttonStyle(.borderedProminent)
            Button { withAnimation(.snappy) { selectedID = nil } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func detailLine(_ s: GasStation) -> String {
        var parts: [String] = []
        if let p = price(s) { parts.append(FuelFormat.price(p)) }
        if let d = distance(s) { parts.append(Format.distance(d)) }
        if !s.address.isEmpty { parts.append(s.address) }
        return parts.joined(separator: " · ")
    }

    private var list: some View {
        List {
            if let message = service.errorMessage {
                Section { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                recommendation
            }
            Section {
                if service.stations.isEmpty {
                    if service.loading {
                        HStack { ProgressView(); Text("正在查找附近加油站…").foregroundStyle(.secondary) }
                    } else if locationManager.location == nil {
                        Text("需要定位权限才能找附近的加油站").foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(radiusKm)) 公里内没有找到加油站").foregroundStyle(.secondary)
                    }
                }
                ForEach(sorted) { s in
                    Button { Navigator.navigate(to: s.coordinate) } label: { row(s) }
                        .buttonStyle(.plain)
                        .listRowBackground(s.id == selectedID ? Color.accentColor.opacity(0.12) : nil)
                }
            } header: {
                Text("附近 \(Int(radiusKm)) 公里 · 点一下就导航")
            } footer: {
                if !service.hasPrices {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(apiKey.isEmpty
                             ? "现在没有油价：加油站来自 Apple 地图。在右上角设置里填入 Google 密钥，就能显示实时油价和性价比推荐。"
                             : "Google 暂时没有这些加油站的油价。")
                        Button("在 Google 地图里看附近油价") { openGoogleMapsSearch() }
                            .font(.footnote.bold())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private var recommendation: some View {
        if let b = best, let cost = totalCost(b), let p = price(b) {
            Button { Navigator.navigate(to: b.coordinate) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("性价比最高", systemImage: "hand.thumbsup.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    HStack(alignment: .firstTextBaseline) {
                        Text(b.name).font(.title3.bold()).lineLimit(1)
                        Spacer()
                        Text(FuelFormat.price(p)).font(.title3.bold().monospacedDigit()).foregroundStyle(.green)
                    }
                    Text(bestSummary(b, cost: cost))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label("导航过去", systemImage: "location.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let n = nearest {
            Button { Navigator.navigate(to: n.coordinate) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("最近的加油站", systemImage: "fuelpump.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(n.name).font(.title3.bold()).lineLimit(1)
                    Text(detailLine(n)).font(.footnote).foregroundStyle(.secondary)
                    Text(service.hasPrices ? "附近没有「\(fuelType.title)」的油价，只能按距离推荐。" : "没有油价时只能按距离推荐。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text("找到加油站后，这里会推荐最划算的一家").foregroundStyle(.secondary)
        }
    }

    private func bestSummary(_ b: GasStation, cost: Double) -> String {
        var text = ""
        if let d = distance(b) { text += Format.distance(d) + "，" }
        text += "加 \(Int(fillLitres)) 升约 \(FuelFormat.money(cost))（含来回油费）"
        if let n = nearestPriced, n.id != b.id, let nc = totalCost(n), nc - cost >= 0.01 {
            text += "，比最近的「\(n.name)」省 \(FuelFormat.money(nc - cost))"
        } else if nearestPriced?.id == b.id {
            text += "，也是最近的一家"
        }
        if let age = FuelFormat.age(price(b)?.updated) { text += "。油价更新于\(age)" }
        return text
    }

    private func row(_ s: GasStation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fuelpump.fill")
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(s.id == best?.id ? Color.green : Color.orange, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(s.name).font(.body).lineLimit(1)
                    if s.id == best?.id {
                        Text("推荐").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green, in: Capsule())
                    }
                }
                Text([distance(s).map(Format.distance), s.address.isEmpty ? nil : s.address]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let p = price(s) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(FuelFormat.price(p))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(p.perLitre == cheapestPrice ? .green : .primary)
                    if let age = FuelFormat.age(p.updated) {
                        Text(age).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else if service.hasPrices {
                Text("无价格").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func openGoogleMapsSearch() {
        let c = locationManager.location?.coordinate
        let center = c.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) } ?? ""
        let app = URL(string: "comgooglemaps://?q=gas+station" + (center.isEmpty ? "" : "&center=\(center)&zoom=14"))
        if let app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = URL(string: "https://www.google.com/maps/search/gas+station/" + (center.isEmpty ? "" : "@\(center),14z")) {
            UIApplication.shared.open(web)
        }
    }
}

/// 地图上的加油站标记：有油价时显示价格
private struct StationPin: View {
    let price: String?
    let isBest: Bool
    let isSelected: Bool

    var body: some View {
        let color: Color = isBest ? .green : .orange
        HStack(spacing: 3) {
            Image(systemName: isBest ? "hand.thumbsup.fill" : "fuelpump.fill")
                .font(.caption2)
            if let price { Text(price).font(.caption.bold().monospacedDigit()) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, price == nil ? 6 : 7)
        .padding(.vertical, 5)
        .background(color, in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
        .shadow(radius: 2)
        .scaleEffect(isSelected ? 1.25 : 1)
        .zIndex(isBest ? 1 : 0)
    }
}

/// 加油设置：油品、加多少升、油耗、搜索范围、Google 密钥
struct GasSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fuel.type") private var fuelType: FuelType = .regular
    @AppStorage("fuel.radiusKm") private var radiusKm = 10.0
    @AppStorage("fuel.fillLitres") private var fillLitres = 40.0
    @AppStorage("fuel.consumption") private var consumption = 10.0
    @AppStorage(GasStationService.keyDefaultsKey) private var apiKey = ""
    @State private var keyDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("油品", selection: $fuelType) {
                        ForEach(FuelType.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("搜索范围", selection: $radiusKm) {
                        ForEach([2.0, 5.0, 10.0, 20.0], id: \.self) { Text("\(Int($0)) 公里").tag($0) }
                    }
                    Stepper("每次加 \(Int(fillLitres)) 升", value: $fillLitres, in: 10...150, step: 5)
                    Stepper(String(format: "油耗 %.1f 升/百公里", consumption), value: $consumption, in: 3...30, step: 0.5)
                } header: {
                    Text("加油")
                } footer: {
                    Text("性价比 = 加这么多升的油钱 + 开过去再回来路上烧掉的油钱，总花费最少的就是推荐。")
                }

                Section {
                    TextField("粘贴 Google 密钥（AIza 开头）", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    if keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != apiKey {
                        Button("保存密钥") { apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    if !apiKey.isEmpty {
                        LabeledContent("本月已查询", value: "\(GasStationService.monthlyGoogleCalls) 次")
                        Button("删除密钥", role: .destructive) { apiKey = ""; keyDraft = "" }
                    }
                } header: {
                    Text("实时油价（Google）")
                } footer: {
                    Text("油价来自 Google 地图的地点接口，需要你自己的密钥：在 console.cloud.google.com 开通结算、启用「Places API (New)」、创建 API 密钥。每月前 1000 次查询免费；App 会缓存结果，同一地方 20 分钟内不会重复查询。密钥只保存在这台手机上。")
                }
            }
            .navigationTitle("加油设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let k = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !k.isEmpty { apiKey = k }
                        dismiss()
                    }
                }
            }
            .onAppear { keyDraft = apiKey }
        }
    }
}
