import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

// MARK: - 训练页「备注」上面的「本次训练地点」卡片
struct GymLocationCard: View {
    @Binding var gym: GymRef?
    @ObservedObject private var gs = GymStore.shared
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("本次训练地点").font(.system(size: 17, weight: .heavy))
                    Spacer()
                    if gym != nil {
                        Label(gs.isPublic ? "公开到地球" : "只自己看", systemImage: gs.isPublic ? "globe.asia.australia.fill" : "lock.fill")
                            .font(.caption.bold()).labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(gs.isPublic ? Color.green : Paper.pencil)
                            .background(Capsule().fill((gs.isPublic ? Color.green : Color.gray).opacity(0.15)))
                    }
                }
                .foregroundStyle(Paper.ink)
                HStack(spacing: 12) {
                    if let g = gym {
                        GymAvatar(url: gs.gym(g.id)?.cover, seed: g.id.isEmpty ? g.name : g.id, size: 44, ring: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            Text(sub(g)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("更换").font(.subheadline.weight(.semibold)).foregroundStyle(Paper.ink)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Paper.pencil)
                    } else {
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(Paper.pencil)
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(Paper.pencil))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("选健身房").font(.headline).foregroundStyle(.primary)
                            Text("打卡到地球，看看还有谁在这练").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Paper.pencil)
                    }
                }
            }
            .paperCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) { GymPicker(selected: $gym) }
    }

    private func sub(_ g: GymRef) -> String {
        var s: [String] = []
        if let info = gs.gym(g.id), info.total > 0 { s.append("\(info.total) 人在这打过卡") }
        if !g.city.isEmpty { s.append(g.city) }
        if s.isEmpty { s.append("新健身房") }
        return s.joined(separator: " · ")
    }
}

// MARK: - 选健身房（附近：已有人打卡的 + 地图上搜到的）
struct GymCandidate: Identifiable, Hashable {
    var ref: GymRef
    var count: Int = 0
    var cover: String? = nil
    var dist: Double? = nil
    var id: String { ref.id.isEmpty ? "poi:\(ref.name):\(ref.lat)" : ref.id }
}

struct GymPicker: View {
    @Binding var selected: GymRef?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gs = GymStore.shared
    @State private var query = ""
    @State private var pois: [GymCandidate] = []
    @State private var pick: GymRef? = nil
    @State private var adding = false
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索健身房名称", text: $query).submitLabel(.search).onSubmit { Task { await searchMap() } }
                        if searching { ProgressView().controlSize(.small) }
                    }
                }
                if gs.locDenied {
                    Section { Text("没有定位权限，附近的健身房排不出来。可以直接搜名字，或到「设置 → X Training → 位置」打开。").font(.footnote).foregroundStyle(.secondary) }
                }
                Section(query.isEmpty ? "附近的健身房" : "搜索结果") {
                    ForEach(candidates) { c in row(c) }
                    if candidates.isEmpty {
                        Text(gs.location == nil && !gs.locDenied ? "正在找附近的健身房…" : "没找到，换个名字试试，或者自己添加").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { adding = true } label: {
                        HStack(spacing: 12) {
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(Brand.pink.opacity(0.6))
                                .frame(width: 46, height: 46).overlay(Image(systemName: "plus").font(.title3).foregroundStyle(Brand.pink))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("没找到？添加新健身房").font(.headline).foregroundStyle(Brand.pink)
                                Text("填名字、拍一张门头或场地照片").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { gs.isPublic }, set: { gs.isPublic = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("公开到打卡地球").font(.headline)
                            Text("只显示健身房和昵称，不显示你的精确位置").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                    if selected != nil {
                        Button("这次不记地点", role: .destructive) { selected = nil; dismiss() }
                    }
                }
            }
            .navigationTitle("本次训练地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Haptic.success()
                    selected = pick ?? selected
                    if let p = selected { gs.lastGym = p }
                    dismiss()
                } label: {
                    Text("就选这家").font(.headline).foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.gradient))
                }
                .buttonStyle(PressScale())
                .disabled((pick ?? selected) == nil).opacity((pick ?? selected) == nil ? 0.5 : 1)
                .padding(.horizontal, 16).padding(.bottom, 8)
                .background(.bar)
            }
            .sheet(isPresented: $adding) {
                AddGymSheet(initialName: query) { g in pick = g; selected = g; gs.lastGym = g; dismiss() }
            }
            .task { pick = selected; gs.locate(); await gs.refresh() }
            .task(id: gs.location?.coordinate.latitude) { await searchMap() }
            .onChange(of: query) { _, q in
                if q.isEmpty { Task { await searchMap() } }
            }
        }
    }

    private func row(_ c: GymCandidate) -> some View {
        let on = (pick ?? selected).map { same($0, c.ref) } ?? false
        return Button { Haptic.tap(); pick = c.ref } label: {
            HStack(spacing: 12) {
                GymAvatar(url: c.cover, seed: c.ref.id.isEmpty ? c.ref.name : c.ref.id, size: 46, ring: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.ref.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(detail(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(on ? Brand.pink : Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    private func detail(_ c: GymCandidate) -> String {
        var s: [String] = []
        if let d = c.dist { s.append(fmtDist(d)) }
        if c.count > 0 { s.append("\(c.count) 人在这打过卡") } else if !c.ref.city.isEmpty { s.append(c.ref.city) }
        return s.isEmpty ? "还没人打卡" : s.joined(separator: " · ")
    }

    private func same(_ a: GymRef, _ b: GymRef) -> Bool {
        if !a.id.isEmpty && !b.id.isEmpty { return a.id == b.id }
        return a.name == b.name && abs(a.lat - b.lat) < 0.003 && abs(a.lon - b.lon) < 0.003
    }

    // 服务器上已有的健身房（有人打过卡）排前面，再加上地图上搜到的
    private var candidates: [GymCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var server = (gs.world?.gyms ?? []).map { g in
            GymCandidate(ref: g.ref, count: g.total, cover: g.cover, dist: gs.distance(g.lat, g.lon))
        }
        if q.isEmpty {
            server = server.filter { ($0.dist ?? .infinity) < 5000 }
        } else {
            server = server.filter { $0.ref.name.localizedCaseInsensitiveContains(q) || $0.ref.city.contains(q) }
        }
        let extra = pois.filter { p in !server.contains { same($0.ref, p.ref) || ($0.ref.name == p.ref.name && ($0.dist ?? 0) < 1000) } }
        var all = server + extra
        all.sort { ($0.dist ?? 1e9) < ($1.dist ?? 1e9) }
        if let s = selected, !all.contains(where: { same($0.ref, s) }) {
            let info = gs.gym(s.id)
            all.insert(GymCandidate(ref: s, count: info?.total ?? 0, cover: info?.cover, dist: gs.distance(s.lat, s.lon)), at: 0)
        }
        return Array(all.prefix(40))
    }

    // 苹果地图找附近的健身房（国内是高德的数据），不用抓别的网站
    private func searchMap() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        let center = gs.location?.coordinate
        if q.isEmpty && center == nil { return }
        searching = true; defer { searching = false }
        var items: [MKMapItem] = []
        if q.isEmpty, let c = center {
            let r = MKLocalPointsOfInterestRequest(center: c, radius: 3000)
            r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
            items = (try? await MKLocalSearch(request: r).start().mapItems) ?? []
            if items.count < 5 {
                let t = MKLocalSearch.Request(); t.naturalLanguageQuery = "健身房"
                t.region = MKCoordinateRegion(center: c, latitudinalMeters: 6000, longitudinalMeters: 6000)
                items += (try? await MKLocalSearch(request: t).start().mapItems) ?? []
            }
        } else {
            let t = MKLocalSearch.Request(); t.naturalLanguageQuery = q.contains("健身") ? q : q + " 健身"
            if let c = center { t.region = MKCoordinateRegion(center: c, latitudinalMeters: 50000, longitudinalMeters: 50000) }
            items = (try? await MKLocalSearch(request: t).start().mapItems) ?? []
        }
        var seen = Set<String>()
        pois = items.compactMap { m in
            guard let name = m.name, seen.insert(name).inserted else { return nil }
            let c = m.placemark.coordinate
            let city = m.placemark.locality ?? m.placemark.administrativeArea ?? ""
            return GymCandidate(ref: GymRef(name: name, city: city, lat: c.latitude, lon: c.longitude), dist: gs.distance(c.latitude, c.longitude))
        }
    }
}

// MARK: - 添加新健身房（名字 + 照片，位置用当前定位）
struct AddGymSheet: View {
    var initialName = ""
    var done: (GymRef) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gs = GymStore.shared
    @State private var name = ""
    @State private var city = ""
    @State private var item: PhotosPickerItem? = nil
    @State private var image: UIImage? = nil
    @State private var camera = false
    @State private var saving = false
    @State private var error = ""
    @State private var mode = 0                 // 0 现在的位置  1 输入地址  2 地图上选
    @State private var address = ""
    @State private var results: [MKMapItem] = []
    @State private var picked: CLLocationCoordinate2D? = nil
    @State private var pickedLabel = ""
    @State private var mapCenter: CLLocationCoordinate2D? = nil

    private var coord: CLLocationCoordinate2D? {
        switch mode {
        case 0: return gs.location?.coordinate
        case 1: return picked
        default: return mapCenter
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Group {
                                if let image { Image(uiImage: image).resizable().scaledToFill() }
                                else { GymAvatar(url: nil, seed: name.isEmpty ? "new" : name, size: 110) }
                            }
                            .frame(width: 110, height: 110).clipShape(Circle())
                            HStack(spacing: 10) {
                                PhotosPicker(selection: $item, matching: .images) { Label("相册", systemImage: "photo") }
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button { camera = true } label: { Label("拍照", systemImage: "camera") }
                                }
                            }
                            .buttonStyle(.bordered).font(.subheadline)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("健身房名字，比如 铁馆 · 国贸店", text: $name)
                    TextField("城市（可不填）", text: $city)
                }
                Section {
                    Picker("位置", selection: $mode) { Text("现在的位置").tag(0); Text("输入地址").tag(1); Text("地图上选").tag(2) }
                        .pickerStyle(.segmented)
                    switch mode {
                    case 0:
                        Text(gs.location == nil ? (gs.locDenied ? "没有定位权限，换成输入地址或地图上选。" : "正在定位…") : "用你现在所在的地方")
                            .font(.footnote).foregroundStyle(.secondary)
                    case 1:
                        HStack {
                            TextField("地区或地址，比如 哈尔滨 中央大街", text: $address).submitLabel(.search).onSubmit { Task { await search() } }
                            Button("查找") { Task { await search() } }.disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        ForEach(results, id: \.self) { m in
                            Button {
                                picked = m.placemark.coordinate
                                pickedLabel = m.name ?? ""
                                if city.isEmpty { city = m.placemark.locality ?? m.placemark.administrativeArea ?? "" }
                                Haptic.tap()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.name ?? "").foregroundStyle(.primary)
                                        Text([m.placemark.administrativeArea, m.placemark.locality, m.placemark.subLocality].compactMap { $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let p = picked, p.latitude == m.placemark.coordinate.latitude, p.longitude == m.placemark.coordinate.longitude {
                                        Image(systemName: "checkmark").foregroundStyle(Brand.pink)
                                    }
                                }
                            }
                        }
                        if let p = picked { GymMapPreview(coord: p).frame(height: 150).listRowInsets(EdgeInsets()) }
                    default:
                        GymMapPicker(center: $mapCenter, start: gs.location?.coordinate).frame(height: 260).listRowInsets(EdgeInsets())
                        Text("拖动地图，把大头针对准健身房门口").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("位置") } footer: {
                    Text("只上传健身房的位置，大家可以在健身房主页看到并导航过去。照片是圆形显示的。")
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("添加新健身房")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("添加") { Task { await save() } }.bold()
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || coord == nil)
                    }
                }
            }
            .onChange(of: item) { _, it in
                Task { if let d = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: d) { image = img } }
            }
            .fullScreenCover(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea() }
            .task {
                name = initialName; gs.locate()
                if let l = gs.location, let p = try? await CLGeocoder().reverseGeocodeLocation(l).first { city = p.locality ?? p.administrativeArea ?? "" }
            }
        }
    }

    private func search() async {
        let q = address.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        results = Array(((try? await MKLocalSearch(request: r).start().mapItems) ?? []).prefix(6))
        if let f = results.first { picked = f.placemark.coordinate; pickedLabel = f.name ?? ""; if city.isEmpty { city = f.placemark.locality ?? f.placemark.administrativeArea ?? "" } }
        if results.isEmpty { error = "没找到这个地方，换个写法试试" } else { error = "" }
    }

    private func save() async {
        guard let c = coord else { return }
        saving = true; defer { saving = false }
        if city.isEmpty, let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first {
            city = p.locality ?? p.administrativeArea ?? ""
        }
        let ref = GymRef(name: name.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces), lat: c.latitude, lon: c.longitude)
        // 网不好也先记下来，保存训练时再补建
        let g = await gs.ensureID(ref) ?? ref
        if let image, !g.id.isEmpty { _ = await gs.upload(photo: image, gym: g.id) }
        Haptic.success()
        done(g)
        dismiss()
    }
}

// 小地图预览：一个圆形大头针
struct GymMapPreview: View {
    var coord: CLLocationCoordinate2D
    var cover: String? = nil
    var seed = "gym"
    var body: some View {
        Map(position: .constant(.region(MKCoordinateRegion(center: coord, latitudinalMeters: 700, longitudinalMeters: 700))), interactionModes: []) {
            Annotation("", coordinate: coord, anchor: .bottom) { GymPinMark(cover: cover, seed: seed) }
        }
        .id("\(coord.latitude),\(coord.longitude)")
    }
}

struct GymPinMark: View {
    var cover: String? = nil
    var seed = "gym"
    var body: some View {
        VStack(spacing: -2) {
            GymAvatar(url: cover, seed: seed, size: 32).overlay(Circle().strokeBorder(.white, lineWidth: 3)).shadow(radius: 3)
            Image(systemName: "triangle.fill").font(.system(size: 9)).foregroundStyle(.white).rotationEffect(.degrees(180))
        }
    }
}

// 地图上选位置：拖地图，中间的大头针就是健身房位置
struct GymMapPicker: View {
    @Binding var center: CLLocationCoordinate2D?
    var start: CLLocationCoordinate2D?
    @State private var pos: MapCameraPosition = .userLocation(fallback: .automatic)
    var body: some View {
        Map(position: $pos)
            .onMapCameraChange(frequency: .onEnd) { ctx in center = ctx.region.center }
            .overlay { GymPinMark().offset(y: -18).allowsHitTesting(false) }
            .onAppear {
                if let s = start ?? center {
                    pos = .region(MKCoordinateRegion(center: s, latitudinalMeters: 800, longitudinalMeters: 800))
                    center = s
                }
            }
    }
}

// 系统相机
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let p: CameraPicker
        init(_ p: CameraPicker) { self.p = p }
        func imagePickerController(_ c: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            p.image = info[.originalImage] as? UIImage; p.dismiss()
        }
        func imagePickerControllerDidCancel(_ c: UIImagePickerController) { p.dismiss() }
    }
}
