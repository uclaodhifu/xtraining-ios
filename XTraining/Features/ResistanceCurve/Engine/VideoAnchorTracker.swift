import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import Vision

// MARK: - 坐标转换

/// 三套坐标统一在这里换算：
/// - 界面坐标：UIKit/SwiftUI，原点左上，单位 pt，图片按 aspectFit 放在 viewSize 里（可能有留边）
/// - Vision 坐标：0...1，原点左下，相对“摆正后的画面”
/// - 引擎坐标：原点左下、y 朝上，x/y 用同一个比例（都除以画面长边），保证角度不变形；再按手机倾斜做重力校正
struct VideoCoordinateConverter: Equatable {
    /// 摆正后的画面尺寸（像素）
    var uprightSize: CGSize
    /// 录制时手机逆时针歪了多少（弧度，CoreMotion 给出；相册视频为 0）。引擎坐标会转回来，让重力竖直向下
    var gravityRoll: Double = 0

    /// aspectFit 后图片在 view 里实际占的区域
    func imageRect(in viewSize: CGSize) -> CGRect {
        guard uprightSize.width > 0, uprightSize.height > 0 else { return CGRect(origin: .zero, size: viewSize) }
        let s = min(viewSize.width / uprightSize.width, viewSize.height / uprightSize.height)
        let w = uprightSize.width * s, h = uprightSize.height * s
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    /// 界面上的点 → Vision 坐标；点在留边里返回 nil
    func viewToVision(_ p: CGPoint, viewSize: CGSize) -> CGPoint? {
        let r = imageRect(in: viewSize)
        guard r.width > 0, r.height > 0, r.contains(p) else { return nil }
        return CGPoint(x: (p.x - r.minX) / r.width, y: 1 - (p.y - r.minY) / r.height)
    }

    /// Vision 坐标 → 界面上的点
    func visionToView(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
        let r = imageRect(in: viewSize)
        return CGPoint(x: r.minX + p.x * r.width, y: r.minY + (1 - p.y) * r.height)
    }

    /// Vision 坐标 → 引擎坐标（等比例 + 重力校正）
    func visionToEngine(_ p: CGPoint) -> CGPoint {
        let side = max(uprightSize.width, uprightSize.height, 1)
        let sx = uprightSize.width / side, sy = uprightSize.height / side
        var x = Double(p.x * sx), y = Double(p.y * sy)
        if gravityRoll != 0 {
            let cx = Double(sx) / 2, cy = Double(sy) / 2
            let c = cos(gravityRoll), s = sin(gravityRoll)   // 手机逆时针歪了多少，画面就逆时针转回多少
            let dx = x - cx, dy = y - cy
            x = cx + dx * c - dy * s
            y = cy + dx * s + dy * c
        }
        return CGPoint(x: x, y: y)
    }

    /// 以 Vision 坐标的点为中心、边长 side（相对短边）的正方形追踪框
    func trackingBox(around p: CGPoint, side: CGFloat = 0.08) -> CGRect {
        let short = max(min(uprightSize.width, uprightSize.height), 1)
        let w = side * short / max(uprightSize.width, 1), h = side * short / max(uprightSize.height, 1)
        let x = min(max(p.x - w / 2, 0), 1 - w), y = min(max(p.y - h / 2, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - 视频方向

enum VideoOrientation {
    /// AVAssetTrack.preferredTransform → Vision 用的图像方向
    static func orientation(from t: CGAffineTransform) -> CGImagePropertyOrientation {
        let mirrored = (t.a * t.d - t.b * t.c) < 0
        let deg = Int((atan2(Double(t.b), Double(t.a)) * 180 / .pi).rounded())
        switch (deg + 360) % 360 {
        case 90: return mirrored ? .leftMirrored : .right
        case 180: return mirrored ? .upMirrored : .down
        case 270: return mirrored ? .rightMirrored : .left
        default: return mirrored ? .downMirrored : .up
        }
    }

    /// 摆正后的画面尺寸
    static func uprightSize(natural: CGSize, transform t: CGAffineTransform) -> CGSize {
        let r = CGRect(origin: .zero, size: natural).applying(t)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }
}

// MARK: - 追踪

/// 追踪要用到的设置
struct TrackingSetup {
    var modality: EquipmentModality
    /// 第一帧上点的锚点（Vision 坐标）。挂片可以点 1~3 个
    var pivot: CGPoint?
    var weights: [CGPoint] = []
    var pulley: CGPoint?
    /// 绳索 / 自由重量：转动中心关节 + 重物关节（一般是手腕）
    var pivotJoint: BodyJoint = .elbow
    var weightJoint: BodyJoint = .wrist
    var gravityRoll: Double = 0
    var targetFPS: Double = 20
    var maxSeconds: Double = 12

    var needsPose: Bool { modality == .cablePulley || modality == .freeWeight }
}

/// 追踪结果
struct TrackingOutput {
    var frames: [TrackedFrame]
    var pivot: CGPoint?             // 引擎坐标
    var pulley: CGPoint?            // 引擎坐标
    var stability: Double           // 0...1，看得清的帧占比
    var converter: VideoCoordinateConverter
    var duration: Double

    func physicsInput(weightLoads: [Double] = [], muscle: MuscleProfileKind?) -> PhysicsInput {
        PhysicsInput(modality: modalityHint, frames: frames, pivot: pivot, weightLoads: weightLoads,
                     pulley: pulley, muscleProfile: muscle, trackingStability: stability)
    }

    var modalityHint: EquipmentModality = .plateLoadedLever
}

enum VideoTrackingError: Error, LocalizedError {
    case noVideoTrack
    case cannotRead
    case tooShort

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "这个文件里没有视频"
        case .cannotRead: return "视频读不出来，换一段试试"
        case .tooShort: return "视频太短，至少录完整的一次动作"
        }
    }
}

/// 用 AVAssetReader 逐帧解码，Vision 追踪锚点 + 识别人体关节，输出重力校准后的引擎坐标
enum VideoAnchorTracker {
    static let minConfidence: Float = 0.3

    /// 摆正后的第一帧（用来让用户点锚点）
    static func firstFrame(url: URL, maxSide: CGFloat = 1280) async -> CGImage? {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: maxSide, height: maxSide)
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        return try? await g.image(at: .zero).image
    }

    /// 视频摆正后的尺寸和方向
    static func geometry(url: URL) async throws -> (size: CGSize, orientation: CGImagePropertyOrientation, duration: Double) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoTrackingError.noVideoTrack }
        let (natural, t) = try await track.load(.naturalSize, .preferredTransform)
        let dur = try await asset.load(.duration).seconds
        return (VideoOrientation.uprightSize(natural: natural, transform: t), VideoOrientation.orientation(from: t), dur)
    }

    static func track(url: URL, setup: TrackingSetup, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> TrackingOutput {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoTrackingError.noVideoTrack }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0.5 else { throw VideoTrackingError.tooShort }

        let orientation = VideoOrientation.orientation(from: transform)
        let conv = VideoCoordinateConverter(uprightSize: VideoOrientation.uprightSize(natural: natural, transform: transform),
                                            gravityRoll: setup.gravityRoll)
        let seconds = min(duration, setup.maxSeconds)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoTrackingError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw VideoTrackingError.cannotRead }

        // 挂片：每个点一个追踪请求，框住点击位置周围 8%
        let seq = VNSequenceRequestHandler()
        let trackers: [VNTrackObjectRequest] = setup.modality == .plateLoadedLever ? setup.weights.map { p in
            let r = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: conv.trackingBox(around: p)))
            r.trackingLevel = .accurate
            return r
        } : []
        var lastObs: [VNDetectedObjectObservation?] = trackers.map { $0.inputObservation as VNDetectedObjectObservation? }
        var offsets: [CGVector] = setup.weights.map { p in
            let b = conv.trackingBox(around: p)
            return CGVector(dx: p.x - b.midX, dy: p.y - b.midY)   // 靠边时框会被挤进画面，记住点和框中心的偏差
        }
        if offsets.count < trackers.count { offsets += Array(repeating: .zero, count: trackers.count - offsets.count) }

        var weights: [[CGPoint?]] = Array(repeating: [], count: trackers.count)
        var hands: [CGPoint?] = [], joints: [CGPoint?] = [], times: [Double] = []
        var seen = 0, valid = 0
        let step = 1 / max(5, min(30, setup.targetFPS))
        var nextTime = 0.0
        var isFirst = true

        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard t + 1e-3 >= nextTime, let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            nextTime = t + step * 0.98
            times.append(t)
            seen += 1
            var frameOK = true

            // 挂片
            for (k, req) in trackers.enumerated() {
                if isFirst {
                    weights[k].append(setup.weights[k])
                    continue
                }
                var point: CGPoint?
                if let obs = lastObs[k] {
                    req.inputObservation = obs
                    try? seq.perform([req], on: pixels, orientation: orientation)
                    if let o = req.results?.first as? VNDetectedObjectObservation {
                        if o.confidence >= minConfidence {
                            lastObs[k] = o
                            point = CGPoint(x: o.boundingBox.midX + offsets[k].dx, y: o.boundingBox.midY + offsets[k].dy)
                        }
                    }
                }
                if point == nil { frameOK = false }
                weights[k].append(point)
            }

            // 人体关节
            if setup.needsPose {
                let pose = VNDetectHumanBodyPoseRequest()
                try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation, options: [:]).perform([pose])
                let pair = pose.results.flatMap { bestPair($0, pivot: setup.pivotJoint, weight: setup.weightJoint) }
                joints.append(pair?.pivot)
                hands.append(pair?.weight)
                if pair == nil { frameOK = false }
            }

            if frameOK { valid += 1 }
            isFirst = false
            let p = min(1, t / seconds)
            progress(p)
        }
        if reader.status == .failed { throw VideoTrackingError.cannotRead }
        guard times.count >= 8 else { throw VideoTrackingError.tooShort }

        // 追丢的帧：前后插值（开头用第一个有效值）
        let filledWeights = weights.map { fillPoints($0) }
        let filledHands = setup.needsPose ? fillPoints(hands) : []
        let filledJoints = setup.needsPose ? fillPoints(joints) : []

        var frames: [TrackedFrame] = []
        for i in times.indices {
            let ws: [CGPoint?] = filledWeights.map { $0[i].map(conv.visionToEngine) }
            let h = filledHands.isEmpty ? nil : filledHands[i].map(conv.visionToEngine)
            let j = filledJoints.isEmpty ? nil : filledJoints[i].map(conv.visionToEngine)
            frames.append(TrackedFrame(time: times[i], weights: ws, hand: h, joint: j))
        }
        progress(1)
        var out = TrackingOutput(frames: frames,
                                 pivot: setup.pivot.map(conv.visionToEngine),
                                 pulley: setup.pulley.map(conv.visionToEngine),
                                 stability: seen == 0 ? 0 : Double(valid) / Double(seen),
                                 converter: conv, duration: seconds)
        out.modalityHint = setup.modality
        return out
    }

    // MARK: - 姿态

    /// 多个人时取画面里最大的那个；左右两侧取两个关节置信度之和更高的一侧
    static func bestPair(_ observations: [VNHumanBodyPoseObservation], pivot: BodyJoint, weight: BodyJoint) -> (pivot: CGPoint, weight: CGPoint)? {
        guard let o = observations.max(by: { bodyArea($0) < bodyArea($1) }) else { return nil }
        var best: (CGPoint, CGPoint, Float)?
        for left in [true, false] {
            guard let a = try? o.recognizedPoint(jointName(pivot, left: left)),
                  let b = try? o.recognizedPoint(jointName(weight, left: left)),
                  a.confidence >= minConfidence, b.confidence >= minConfidence else { continue }
            let score = a.confidence + b.confidence
            if best == nil || score > best!.2 { best = (a.location, b.location, score) }
        }
        return best.map { (pivot: $0.0, weight: $0.1) }
    }

    static func jointName(_ j: BodyJoint, left: Bool) -> VNHumanBodyPoseObservation.JointName {
        switch j {
        case .shoulder: return left ? .leftShoulder : .rightShoulder
        case .elbow: return left ? .leftElbow : .rightElbow
        case .wrist: return left ? .leftWrist : .rightWrist
        case .hip: return left ? .leftHip : .rightHip
        case .knee: return left ? .leftKnee : .rightKnee
        case .ankle: return left ? .leftAnkle : .rightAnkle
        }
    }

    private static func bodyArea(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.2 }), pts.count > 2 else { return 0 }
        let xs = pts.map(\.location.x), ys = pts.map(\.location.y)
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }

    // MARK: - 插值

    static func fillPoints(_ a: [CGPoint?]) -> [CGPoint?] {
        let known = a.enumerated().compactMap { i, p in p.map { (i, $0) } }
        guard let first = known.first, let last = known.last else { return a }
        var out = a
        var k = 0
        for i in a.indices where a[i] == nil {
            if i < first.0 { out[i] = first.1; continue }
            if i > last.0 { out[i] = last.1; continue }
            while k + 1 < known.count && known[k + 1].0 < i { k += 1 }
            let l = known[k], r = known[k + 1]
            let t = CGFloat(i - l.0) / CGFloat(r.0 - l.0)
            out[i] = CGPoint(x: l.1.x + (r.1.x - l.1.x) * t, y: l.1.y + (r.1.y - l.1.y) * t)
        }
        return out
    }
}
