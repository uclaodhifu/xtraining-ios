import SwiftUI
import PhotosUI
import MapKit
import CoreLocation

// MARK: - 健身房主页：圆形大头像、打卡人数、最近在这练的人、大家传的照片
struct GymPage: View {
    var gymID: String
    @EnvironmentObject var store: Store
    @ObservedObject private var gs = GymStore.shared
    @State private var item: PhotosPickerItem? = nil
    @State private var uploading = false
    @State private var toast = ""
    @State private var big: String? = nil

    private var g: GymInfo? { gs.gym(gymID) }

    var body: some View {
        ScrollView {
            if let g {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        GymAvatar(url: g.cover, seed: g.id, size: 118, ring: true)
                        Text(g.name).font(.system(size: 24, weight: .heavy)).multilineTextAlignment(.center).padding(.top, 6)
                        Text([g.city, g.by.isEmpty ? "" : "由 @\(g.by) 添加"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        stat("\(g.total)", "打过卡的人")
                        stat("\(g.week)", "本周")
                        stat(g.top.first ?? "—", "最常练")
                    }
                    GymLocationBox(g: g)
                    card("最近在这练的人", note: "只显示公开的") {
                        if g.recent.isEmpty {
                            Text("还没有人公开打卡").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(g.recent, id: \.uid) { p in
                                        VStack(spacing: 3) {
                                            PersonDot(nick: p.nick, uid: p.uid, size: 48)
                                            Text(p.uid == gs.uid ? "我" : p.nick).font(.caption2).lineLimit(1).frame(maxWidth: 56)
                                            Text(p.parts.isEmpty ? when(p.t) : p.parts.joined(separator: "·")).font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.pink).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    card("健身房照片", note: "大家上传 · 后台审核") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(g.photos, id: \.self) { u in
                                    GymAvatar(url: u, seed: g.id, size: 62).onTapGesture { big = u }
                                }
                                ForEach(Array((gs.myUploads[g.id] ?? []).enumerated()), id: \.offset) { _, d in
                                    GymAvatar(url: nil, seed: g.id, size: 62, local: d).overlay(alignment: .bottom) { pendingBadge }
                                }
                                ForEach(g.pending.filter { $0.uid == gs.uid && (gs.myUploads[g.id] ?? []).isEmpty }, id: \.url) { p in
                                    GymAvatar(url: p.url, seed: g.id, size: 62).overlay(alignment: .bottom) { pendingBadge }
                                }
                                PhotosPicker(selection: $item, matching: .images) {
                                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(Color(.tertiaryLabel))
                                        .frame(width: 62, height: 62)
                                        .overlay { if uploading { ProgressView() } else { VStack(spacing: 1) { Image(systemName: "plus"); Text("传照片").font(.system(size: 10)) }.foregroundStyle(.secondary) } }
                                }
                                .disabled(uploading)
                            }
                            .padding(.vertical, 4)
                        }
                        Text("第一张照片会直接当头像，之后的照片后台审核，后台也能换头像。").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { checkinHere(g) } label: {
                        Text("今天在这打卡").font(.headline).foregroundStyle(Brand.ink)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.gradient))
                    }
                    .buttonStyle(PressScale())
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(nil)
        .overlay(alignment: .top) {
            if !toast.isEmpty {
                Text(toast).font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(get: { big.map(StrID.init) }, set: { big = $0?.id })) { s in
            AsyncImage(url: URL(string: s.id)) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                .presentationDetents([.medium, .large])
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                uploading = true; defer { uploading = false; item = nil }
                guard let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                let ok = await gs.upload(photo: img, gym: gymID)
                show(ok ? "已上传，审核后大家就能看到" : "上传失败，网络不好再试一次")
                if ok { await gs.refresh() }
            }
        }
        .refreshable { await gs.refresh() }
    }

    private var pendingBadge: some View {
        Text("审核中").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 4).background(Capsule().fill(Color.orange)).offset(y: 4)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 19, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func card<C: View>(_ title: String, note: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func when(_ t: Double) -> String {
        let d = Date().timeIntervalSince1970 - t / 1000
        return d < 3600 ? "刚刚" : d < 86400 ? "\(Int(d / 3600)) 小时前" : "\(Int(d / 86400)) 天前"
    }

    private func show(_ s: String) {
        withAnimation(.snappy) { toast = s }
        Task { try? await Task.sleep(for: .seconds(2.2)); withAnimation(.snappy) { toast = "" } }
    }

    // 今天练过就带上部位；还没练也能先打卡
    private func checkinHere(_ g: GymInfo) {
        Haptic.success()
        if !gs.isPublic { gs.isPublic = true }
        let ws = store.todays
        let parts = Parts.all.filter { p in ws.contains { $0.parts.contains(p) } }
        if var w = ws.max(by: { $0.createdAt < $1.createdAt }) {
            w.gym = g.ref; store.upsert(w)
            gs.checkin(workoutID: w.id, gym: g.ref, parts: parts, date: Day.today)
        } else {
            gs.checkin(workoutID: "gym-" + Day.today, gym: g.ref, parts: [], date: Day.today)
        }
        show("已打卡 ✓")
    }
}

// 健身房位置：大家都能看，能导航（高德 / 苹果地图），位置不准可以纠正
struct GymLocationBox: View {
    var g: GymInfo
    @ObservedObject private var gs = GymStore.shared
    @State private var address = ""
    @State private var askNav = false
    @State private var fixing = false
    @State private var copied = false
    private var coord: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("健身房位置").font(.subheadline.bold())
                Spacer()
                Button("位置不对？纠正") { fixing = true }.font(.caption).foregroundStyle(.secondary)
            }
            GymMapPreview(coord: coord, cover: g.cover, seed: g.id)
                .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(address.isEmpty ? (g.city.isEmpty ? "正在查地址…" : g.city) : address).font(.subheadline)
                if let d = gs.distance(g.lat, g.lon) { Text("距你 \(fmtDist(d))").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Button { askNav = true } label: {
                    Text("导航去这里").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.gradient))
                }
                Button {
                    UIPasteboard.general.string = [g.name, address.isEmpty ? g.city : address].filter { !$0.isEmpty }.joined(separator: " ")
                    Haptic.success(); copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Text(copied ? "已复制 ✓" : "复制地址").font(.subheadline.bold()).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
                }
            }
            .buttonStyle(PressScale())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .confirmationDialog("用哪个地图导航？", isPresented: $askNav, titleVisibility: .visible) {
            Button("高德地图") { openAmap() }
            Button("苹果地图") { openApple() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $fixing) { GymFixSheet(g: g) }
        .task(id: g.id) {
            let l = CLLocation(latitude: g.lat, longitude: g.lon)
            if let p = try? await CLGeocoder().reverseGeocodeLocation(l).first {
                address = [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare].compactMap { $0 }
                    .reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.joined()
            }
        }
    }

    private func openAmap() {
        let name = g.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // 坐标已经是国内地图坐标（dev=0 不再偏移）
        if let u = URL(string: "iosamap://path?sourceApplication=XTraining&dlat=\(g.lat)&dlon=\(g.lon)&dname=\(name)&dev=0&t=0"), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
        } else if let w = URL(string: "https://uri.amap.com/marker?position=\(g.lon),\(g.lat)&name=\(name)&coordinate=gaode&callnative=1") {
            UIApplication.shared.open(w)
        }
    }
    private func openApple() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = g.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

// 纠正位置：拖地图对准健身房门口。添加的人改了直接生效，其他人改了后台确认
struct GymFixSheet: View {
    var g: GymInfo
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gs = GymStore.shared
    @State private var center: CLLocationCoordinate2D? = nil
    @State private var sending = false
    @State private var msg = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GymMapPicker(center: $center, start: CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(msg.isEmpty ? "拖动地图，把大头针对准「\(g.name)」门口" : msg).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
            .navigationTitle("纠正健身房位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("提交") {
                            guard let c = center else { return }
                            Task {
                                sending = true; defer { sending = false }
                                var city = g.city
                                if let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first { city = p.locality ?? p.administrativeArea ?? city }
                                if await GymAPI.fix(gym: g.id, uid: gs.uid, lat: c.latitude, lon: c.longitude, city: city) {
                                    Haptic.success(); await gs.refresh(); dismiss()
                                } else { msg = "提交失败，网络不好再试一次" }
                            }
                        }.bold()
                    }
                }
            }
        }
    }
}
