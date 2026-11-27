import XCTest
import CoreGraphics
@testable import XTraining

final class ResistancePhysicsEngineTests: XCTestCase {
    typealias E = ResistancePhysicsEngine

    // MARK: - 造数据：一根绕支点转动的杠杆

    /// 杠杆角度（度，水平 = 0，朝上为正）按 3 次来回变化，返回每帧挂片位置
    private func leverFrames(pivot: CGPoint, radius: Double, from a: Double, to b: Double,
                             reps: Int = 3, fps: Double = 20, noise: Double = 0) -> [TrackedFrame] {
        let perRep = 40
        var frames: [TrackedFrame] = []
        for i in 0..<(perRep * reps) {
            let phase = Double(i % perRep) / Double(perRep)        // 0→1→0 一次来回
            let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let deg = a + (b - a) * t
            let rad = deg * .pi / 180
            let jitter = noise * sin(Double(i) * 12.9898)          // 固定的“噪声”，结果可复现
            let w = CGPoint(x: pivot.x + CGFloat(radius * cos(rad) + jitter),
                            y: pivot.y + CGFloat(radius * sin(rad) - jitter))
            frames.append(TrackedFrame(time: Double(i) / fps, weight: w))
        }
        return frames
    }

    private func analyzeLever(from a: Double, to b: Double, noise: Double = 0, reversed: Bool = false) throws -> ResistanceAnalysisResult {
        let p = CGPoint(x: 0.4, y: 0.5)
        var frames = leverFrames(pivot: p, radius: 0.3, from: a, to: b, noise: noise)
        if reversed { frames.reverse() }
        return try E.analyze(PhysicsInput(modality: .plateLoadedLever, frames: frames, pivot: p))
    }

    // MARK: - 四种典型曲线

    func testDescendingCurve() throws {
        // 杠杆从水平往上抬到 60°：片子越来越高，力臂越来越短 → 拉长位最重
        let r = try analyzeLever(from: 0, to: 60)
        XCTAssertEqual(r.curvePattern, .descending)
        XCTAssertLessThanOrEqual(r.peakRomPercent, 10)
        XCTAssertEqual(r.points.count, 21)
        XCTAssertEqual(r.points.map(\.resistancePct).max() ?? 0, 100, accuracy: 0.001)
    }

    func testAscendingCurve() throws {
        // 杠杆从水平下方 70° 抬到水平：力臂越来越长 → 缩短位最重
        let r = try analyzeLever(from: -70, to: 0)
        XCTAssertEqual(r.curvePattern, .ascending)
        XCTAssertGreaterThanOrEqual(r.peakRomPercent, 90)
        XCTAssertGreaterThan(r.dropoffPercent, 50)
    }

    func testBellShapedCurve() throws {
        // 从下方 60° 抬到上方 60°：中间水平时最重
        let r = try analyzeLever(from: -60, to: 60)
        XCTAssertEqual(r.curvePattern, .bellShaped)
        XCTAssertTrue((40...60).contains(r.peakRomPercent), "peak \(r.peakRomPercent)")
    }

    func testFlatCurve() throws {
        // 只在水平附近 ±5° 动：力臂几乎不变
        let r = try analyzeLever(from: -5, to: 5)
        XCTAssertEqual(r.curvePattern, .flat)
        XCTAssertLessThan(r.dropoffPercent, 8)
    }

    func testDirectionDoesNotDependOnWhereRecordingStarts() throws {
        // 用户反馈“上升下降判反了”：倒着放同一段视频，结论必须一样
        let a = try analyzeLever(from: -70, to: 0)
        let b = try analyzeLever(from: -70, to: 0, reversed: true)
        XCTAssertEqual(a.curvePattern, b.curvePattern)
        XCTAssertEqual(a.peakRomPercent, b.peakRomPercent)
    }

    func testNoisyTrackingStillClassifies() throws {
        let r = try analyzeLever(from: -70, to: 0, noise: 0.004)
        XCTAssertEqual(r.curvePattern, .ascending)
    }

    func testRepCount() throws {
        let r = try analyzeLever(from: 0, to: 60)
        XCTAssertEqual(r.reps, 3)
    }

    // MARK: - 分类阈值

    func testClassifyThresholds() {
        XCTAssertEqual(E.classify((0..<21).map { 100 - Double($0) * 0.3 }).pattern, .flat)          // 掉 6%
        XCTAssertEqual(E.classify((0..<21).map { 100 - Double($0) * 2 }).pattern, .descending)
        XCTAssertEqual(E.classify((0..<21).map { 60 + Double($0) * 2 }).pattern, .ascending)
        XCTAssertEqual(E.classify((0..<21).map { 70 + 30 * exp(-pow((Double($0) - 10) / 4, 2)) }).pattern, .bellShaped)
        // 两头高中间低：不属于任何一种
        XCTAssertEqual(E.classify((0..<21).map { 70 + 30 * pow((Double($0) - 10) / 10, 2) }).pattern, .complex)
    }

    // MARK: - 四种模式的公式

    func testLeverFormula() {
        let p = CGPoint(x: 0, y: 0)
        XCTAssertEqual(E.leverFactor(pivot: p, weight: CGPoint(x: 1, y: 0))!, 1, accuracy: 1e-9)       // 水平
        XCTAssertEqual(E.leverFactor(pivot: p, weight: CGPoint(x: 0, y: 1))!, 0, accuracy: 1e-9)       // 竖直
        XCTAssertEqual(E.leverFactor(pivot: p, weight: CGPoint(x: 1, y: 1))!, sqrt(0.5), accuracy: 1e-9)
        XCTAssertNil(E.leverFactor(pivot: p, weight: p))
    }

    func testMultiPlateTorque() {
        // 同一根杠杆上两个挂片：一个在支点右边 0.3（20kg），一个在左边 0.1（10kg）
        let p = CGPoint(x: 0.5, y: 0.5)
        let w1 = CGPoint(x: 0.8, y: 0.5), w2 = CGPoint(x: 0.4, y: 0.5)
        let t = E.leverTorque(pivot: p, weights: [w1, w2], loads: [20, 10], radii: [0.3, 0.1])!
        XCTAssertEqual(t, 20 * 0.3 - 10 * 0.1, accuracy: 1e-6)
    }

    func testMultiPlateLeverAnalysis() throws {
        // 两个挂片随杠杆一起转（第二个挂片在杠杆中段）
        let p = CGPoint(x: 0.4, y: 0.5)
        let outer = leverFrames(pivot: p, radius: 0.3, from: -70, to: 0)
        let frames = outer.map { f -> TrackedFrame in
            let w = f.weights[0]!
            let mid = CGPoint(x: p.x + (w.x - p.x) * 0.5, y: p.y + (w.y - p.y) * 0.5)
            return TrackedFrame(time: f.time, weights: [w, mid])
        }
        let r = try E.analyze(PhysicsInput(modality: .plateLoadedLever, frames: frames, pivot: p, weightLoads: [20, 20]))
        XCTAssertEqual(r.curvePattern, .ascending)
    }

    func testCableFormula() {
        let j = CGPoint(x: 0, y: 0), h = CGPoint(x: 1, y: 0)
        XCTAssertEqual(E.cableFactor(joint: j, hand: h, pulley: CGPoint(x: 1, y: 1))!, 1, accuracy: 1e-9)   // 垂直
        XCTAssertEqual(E.cableFactor(joint: j, hand: h, pulley: CGPoint(x: 2, y: 0))!, 0, accuracy: 1e-9)   // 同一条线
    }

    func testCableAnalysis() throws {
        // 绳索侧平举：肩在 (0.5,0.6)，滑轮在脚边另一侧低处，手臂从垂下抬到水平
        let j = CGPoint(x: 0.5, y: 0.6), c = CGPoint(x: 0.3, y: 0.05)
        var frames: [TrackedFrame] = []
        for i in 0..<120 {
            let phase = Double(i % 40) / 40, t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let rad = (-90 + 90 * t) * .pi / 180
            let h = CGPoint(x: j.x + CGFloat(0.25 * cos(rad)), y: j.y + CGFloat(0.25 * sin(rad)))
            frames.append(TrackedFrame(time: Double(i) / 20, hand: h, joint: j))
        }
        let r = try E.analyze(PhysicsInput(modality: .cablePulley, frames: frames, pulley: c, muscleProfile: .shoulderRaise))
        XCTAssertEqual(r.points.count, 21)
        XCTAssertNotNil(r.lengthenedMatch)
        // 绳子从对侧低处过来，手臂垂下时也有阻力（不像哑铃那样几乎为 0）
        XCTAssertGreaterThan(r.points[0].resistancePct, 30)
    }

    func testFreeWeightCurlIsBellShaped() throws {
        // 哑铃弯举：肘在 (0.5,0.5)，前臂从垂下 -90° 弯到 +60°，水平时最重
        let j = CGPoint(x: 0.5, y: 0.5)
        var frames: [TrackedFrame] = []
        for i in 0..<120 {
            let phase = Double(i % 40) / 40, t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let rad = (-90 + 150 * t) * .pi / 180
            let h = CGPoint(x: j.x + CGFloat(0.2 * cos(rad)), y: j.y + CGFloat(0.2 * sin(rad)))
            frames.append(TrackedFrame(time: Double(i) / 20, hand: h, joint: j))
        }
        let r = try E.analyze(PhysicsInput(modality: .freeWeight, frames: frames, muscleProfile: .bicepsCurl))
        XCTAssertEqual(r.curvePattern, .bellShaped)
        XCTAssertNotNil(r.points[10].muscleForcePct)
    }

    func testLateralRaiseIsAscending() throws {
        let j = CGPoint(x: 0.5, y: 0.6)
        let frames = leverFrames(pivot: j, radius: 0.25, from: -90, to: 0).map {
            TrackedFrame(time: $0.time, hand: $0.weights[0], joint: j)
        }
        let r = try E.analyze(PhysicsInput(modality: .freeWeight, frames: frames, muscleProfile: .shoulderRaise))
        XCTAssertEqual(r.curvePattern, .ascending)
        XCTAssertEqual(r.peakWarning?.hasPrefix("顶峰位过载"), true)
    }

    func testSelectorizedCamUsesLibrary() throws {
        let lib = MachineProfileLibrary.load()   // 测试跑在 App 里，JSON 在 App 包里
        XCTAssertGreaterThanOrEqual(lib.profiles.count, 10)
        for p in lib.profiles {
            XCTAssertEqual(p.defaultCurve.count, 21, p.id)
            XCTAssertEqual(p.muscleCurve.count, 21, p.id)
        }
        let leg = try XCTUnwrap(lib.match("腿屈伸"))
        XCTAssertEqual(leg.id, "leg_extension")
        let r = E.analyze(profile: leg, confidence: 0.5)
        XCTAssertEqual(r.modality, .selectorizedCam)
        XCTAssertEqual(r.curvePattern, .ascending)
        XCTAssertEqual(r.matchedMachineId, "leg_extension")
        XCTAssertEqual(r.camWarning?.contains("认得不太准"), true)
        XCTAssertNotNil(lib.profile(id: "tbar_row_plate"))
        XCTAssertNotNil(lib.match("T杠划船"))
    }

    // MARK: - 肌群对比

    func testMuscleComparison() {
        let back = E.muscleCurve(.backRow)
        XCTAssertEqual(back.first ?? 0, 100, accuracy: 0.001)
        // 背部划船配“拉长位最重”的器械：拉长位很匹配
        let desc = (0..<21).map { 100 - Double($0) * 2 }
        XCTAssertGreaterThan(E.compare(resistance: desc, muscle: back).lengthenedMatch, 90)
        // 配“越往后越重”的器械：拉长位不匹配，顶峰过载
        let asc = (0..<21).map { 40 + Double($0) * 3 }
        let c = E.compare(resistance: asc, muscle: back)
        XCTAssertLessThan(c.lengthenedMatch, 60)
        XCTAssertEqual(c.peakWarning?.hasPrefix("顶峰位过载"), true)
    }

    func testErrors() {
        XCTAssertThrowsError(try E.analyze(PhysicsInput(modality: .plateLoadedLever, frames: []))) {
            XCTAssertEqual($0 as? ResistanceAnalysisError, .missingAnchor(.pivot))
        }
        let still = (0..<30).map { TrackedFrame(time: Double($0), weight: CGPoint(x: 0.7, y: 0.5)) }
        XCTAssertThrowsError(try E.analyze(PhysicsInput(modality: .plateLoadedLever, frames: still, pivot: CGPoint(x: 0.4, y: 0.5)))) {
            XCTAssertEqual($0 as? ResistanceAnalysisError, .tooLittleMotion)
        }
    }
}
