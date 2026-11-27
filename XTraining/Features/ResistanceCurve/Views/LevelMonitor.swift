import Foundation
import CoreMotion
import SwiftUI

/// 用 CoreMotion 看手机有没有摆正。歪超过 15° 给黄色提醒；录像期间记下平均倾斜角，分析时用来做重力校正。
@MainActor
final class LevelMonitor: ObservableObject {
    static let warnDegrees = 15.0

    /// 当前倾斜（度，逆时针为正，已经去掉横竖屏的 90° 整数倍）
    @Published private(set) var tiltDegrees: Double = 0
    @Published private(set) var isAvailable = false
    /// 手机平放（屏幕朝上/朝下）时倾斜角没有意义
    @Published private(set) var isFlat = false

    private let manager = CMMotionManager()
    private var samples: [Double] = []
    private var recording = false

    var isTilted: Bool { !isFlat && abs(tiltDegrees) > Self.warnDegrees }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            MainActor.assumeIsolated { self.update(g) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func beginRecording() {
        samples = []
        recording = true
    }

    /// 录像期间的平均倾斜（弧度）；没有数据返回 0
    func endRecording() -> Double {
        recording = false
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2] * .pi / 180
    }

    private func update(_ g: CMAcceleration) {
        isFlat = abs(g.z) > 0.8
        let deg = Self.residualTilt(gx: g.x, gy: g.y)
        tiltDegrees = deg
        if recording && !isFlat { samples.append(deg) }
    }

    /// 重力在屏幕平面上的方向 → 手机逆时针转了多少度，再去掉 90° 的整数倍（横着拍也算摆正）
    nonisolated static func residualTilt(gx: Double, gy: Double) -> Double {
        let a = atan2(-gx, -gy) * 180 / .pi
        var r = a.truncatingRemainder(dividingBy: 90)
        if r > 45 { r -= 90 }
        if r < -45 { r += 90 }
        return r
    }
}

/// 水平仪小卡片
struct LevelIndicator: View {
    @ObservedObject var level: LevelMonitor

    var body: some View {
        let tilted = level.isTilted
        let color: Color = tilted ? Color(hex: 0xf59f00) : Color(hex: 0x2f9e44)
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 3)
                Capsule().fill(color).frame(width: 32, height: 3)
                    .rotationEffect(.degrees(level.isFlat ? 0 : -level.tiltDegrees))
                Circle().fill(color).frame(width: 6, height: 6)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                if level.isFlat {
                    Text("手机竖起来再录").font(.subheadline.bold())
                    Text("放稳、对着器械侧面，人和器械都在画面里").font(.caption).foregroundStyle(.secondary)
                } else if tilted {
                    Text("手机歪了 \(Int(abs(level.tiltDegrees).rounded()))°").font(.subheadline.bold()).foregroundStyle(color)
                    Text("录的时候摆正，阻力方向才算得准").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("手机是正的").font(.subheadline.bold()).foregroundStyle(color)
                    Text("放稳、对着器械侧面，人和器械都在画面里").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .animation(.easeOut(duration: 0.2), value: tilted)
    }
}
