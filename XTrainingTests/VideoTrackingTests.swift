import XCTest
import CoreGraphics
import ImageIO
@testable import XTraining

final class VideoTrackingTests: XCTestCase {

    func testOrientationFromPreferredTransform() {
        XCTAssertEqual(VideoOrientation.orientation(from: .identity), .up)
        // iPhone 竖着拍：画面存成横的，preferredTransform 转 90°
        XCTAssertEqual(VideoOrientation.orientation(from: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)), .right)
        XCTAssertEqual(VideoOrientation.orientation(from: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), .down)
        XCTAssertEqual(VideoOrientation.orientation(from: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
    }

    func testUprightSize() {
        let s = VideoOrientation.uprightSize(natural: CGSize(width: 1920, height: 1080),
                                             transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0))
        XCTAssertEqual(s.width, 1080, accuracy: 0.5)
        XCTAssertEqual(s.height, 1920, accuracy: 0.5)
    }

    func testAspectFitRoundTrip() {
        // 竖屏视频放在一个偏宽的 view 里：左右有留边
        let c = VideoCoordinateConverter(uprightSize: CGSize(width: 1080, height: 1920))
        let view = CGSize(width: 400, height: 400)
        let rect = c.imageRect(in: view)
        XCTAssertEqual(rect.height, 400, accuracy: 0.01)
        XCTAssertEqual(rect.width, 225, accuracy: 0.01)
        XCTAssertEqual(rect.minX, 87.5, accuracy: 0.01)
        XCTAssertNil(c.viewToVision(CGPoint(x: 10, y: 200), viewSize: view))           // 点在留边上
        let v = c.viewToVision(CGPoint(x: 200, y: 100), viewSize: view)!
        XCTAssertEqual(v.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(v.y, 0.75, accuracy: 1e-6)                                         // Vision 原点在左下
        let back = c.visionToView(v, viewSize: view)
        XCTAssertEqual(back.x, 200, accuracy: 1e-6)
        XCTAssertEqual(back.y, 100, accuracy: 1e-6)
    }

    func testEngineCoordinatesKeepAngles() {
        // 竖屏画面里一根 45° 的杠杆，换到引擎坐标后还应该是 45°（x、y 用同一个比例）
        let c = VideoCoordinateConverter(uprightSize: CGSize(width: 1000, height: 2000))
        let a = c.visionToEngine(CGPoint(x: 0.2, y: 0.2))
        let b = c.visionToEngine(CGPoint(x: 0.4, y: 0.3))        // 像素上 dx = 200, dy = 200
        XCTAssertEqual(Double(b.x - a.x), Double(b.y - a.y), accuracy: 1e-9)
    }

    func testGravityRollCorrection() {
        // 手机逆时针歪了 10°：画面里竖直的线看起来往右偏 10°，校正后应回到竖直
        let roll = 10 * Double.pi / 180
        let c = VideoCoordinateConverter(uprightSize: CGSize(width: 1000, height: 1000), gravityRoll: roll)
        let top = CGPoint(x: 0.5 + 0.3 * sin(roll), y: 0.5 + 0.3 * cos(roll))
        let a = c.visionToEngine(CGPoint(x: 0.5, y: 0.5)), b = c.visionToEngine(top)
        XCTAssertEqual(Double(b.x - a.x), 0, accuracy: 1e-9)
    }

    func testTrackingBoxStaysInsideFrame() {
        let c = VideoCoordinateConverter(uprightSize: CGSize(width: 1080, height: 1920))
        let box = c.trackingBox(around: CGPoint(x: 0.99, y: 0.01))
        XCTAssertGreaterThanOrEqual(box.minX, 0)
        XCTAssertLessThanOrEqual(box.maxX, 1.000001)
        XCTAssertGreaterThanOrEqual(box.minY, 0)
        // 像素上是正方形
        XCTAssertEqual(box.width * 1080, box.height * 1920, accuracy: 0.01)
    }

    func testFillPointsInterpolatesGaps() {
        let a: [CGPoint?] = [nil, CGPoint(x: 0, y: 0), nil, nil, CGPoint(x: 3, y: 6), nil]
        let f = VideoAnchorTracker.fillPoints(a)
        XCTAssertEqual(f[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(f[2]!.x, 1, accuracy: 1e-9)
        XCTAssertEqual(f[3]!.y, 4, accuracy: 1e-9)
        XCTAssertEqual(f[5], CGPoint(x: 3, y: 6))
    }

    func testClassifierFallsBackWithoutModel() async {
        // 测试包里没有 Core ML 模型：必须能跑，并退回手动选择
        let service = EquipmentClassifierService(bundle: Bundle(for: Self.self))
        XCTAssertFalse(service.isAvailable)
        let img = makeImage()
        let outcome = await service.recognize(img)
        XCTAssertEqual(outcome, .unavailable)
        let preds = await service.classify(img, orientation: .up)
        XCTAssertTrue(preds.isEmpty)
        let none = await UnavailableEquipmentClassifier().recognize(img)
        XCTAssertEqual(none, .unavailable)
    }

    private func makeImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()!
    }
}
