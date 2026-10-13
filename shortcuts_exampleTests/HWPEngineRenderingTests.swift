import RivoDocumentEngine
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

/// Equations and WMF chart previews are drawn from the engine's layout and playback.
@MainActor
final class HWPEngineRenderingTests: XCTestCase {
    func testMetafileTextDecodesTheFontCharsetThenFallsBack() {
        XCTAssertEqual(hwpMetafileText(hex: "b0a1b3aa", charset: 129), "가나")
        XCTAssertEqual(hwpMetafileText(hex: "82a082a2", charset: 128), "あい")
        XCTAssertEqual(hwpMetafileText(hex: "c4e3bac3", charset: 134), "你好")
        XCTAssertEqual(hwpMetafileText(hex: "a4a4a4e5", charset: 136), "中文")
        XCTAssertEqual(hwpMetafileText(hex: "cff0e8e2", charset: 204), "Прив")
        // Not CP949 (a lead byte without its trail byte): Windows-1252.
        XCTAssertEqual(hwpMetafileText(hex: "41b0", charset: 129), "A°")
        XCTAssertEqual(hwpMetafileText(hex: "", charset: 129), "")
    }

    func testEquationAndMetafileDrawInk() throws {
        let equation = HWPDocumentEquation(script: "{-b pm sqrt {b^{2} - 4ac}} over {2a}", fontSizePoints: 14,
            colorRGB: 0x1F3A93, baselinePercent: 80, fontName: nil)
        let size = CGSize(width: 200, height: 80)
        XCTAssertGreaterThan(Self.inkedPixels(try render(HWPEquationCanvasView(equation: equation), size: size)), 200)
        let formula = HWPEquationLayout.formula(script: equation.script, fontSize: 14, width: 200, height: 80,
            measure: HWPEquationCanvasView.measure)
        XCTAssertEqual(formula.rules.count, 2)
        XCTAssertLessThanOrEqual(formula.width, 200.0001)

        for charset in [0, 128, 129, 134, 136, 204] {
            let image = try render(HWPMetafileCanvasView(metafile: Self.chart(charset: charset)), size: size)
            XCTAssertGreaterThan(Self.inkedPixels(image), 1_000, "charset \(charset)")
        }
    }

    // MARK: Helpers

    private func render(_ view: some View, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(.white))
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// Pixels that are not white.
    private static func inkedPixels(_ image: CGImage) -> Int {
        let values = pixels(image, width: image.width, height: image.height)
        return stride(from: 0, to: values.count, by: 4).reduce(0) { count, offset in
            count + (values[offset..<offset + 3].contains { $0 < 230 } ? 1 : 0)
        }
    }

    /// A WMF of 1000 × 500 logical units exercising every record the player draws, its text in `charset`.
    static func chart(charset: Int) -> HWPDocumentMetafile {
        var records: [[UInt8]] = []
        func words(_ values: [Int]) -> [UInt8] { values.flatMap { [UInt8($0 & 0xFF), UInt8(($0 >> 8) & 0xFF)] } }
        func record(_ function: Int, _ parameters: [UInt8]) {
            var parameters = parameters
            if parameters.count % 2 == 1 { parameters.append(0) }
            let size = 3 + parameters.count / 2
            records.append(words([size & 0xFFFF, size >> 16, function]) + parameters)
        }
        func colorRef(_ red: Int, _ green: Int, _ blue: Int) -> [UInt8] { [UInt8(red), UInt8(green), UInt8(blue), 0] }
        let text: [UInt8] = switch charset {
        case 128: [0x82, 0xA0, 0x82, 0xA2] // あい
        case 129: [0xB0, 0xA1, 0xB3, 0xAA] // 가나
        case 134: [0xC4, 0xE3, 0xBA, 0xC3] // 你好
        case 136: [0xA4, 0xA4, 0xA4, 0xE5] // 中文
        case 204: [0xCF, 0xF0, 0xE8, 0xE2] // Прив
        default: [0x51, 0x31, 0x20, 0x80]
        }
        record(0x001E, [])
        record(0x020B, words([0, 0]))
        record(0x020C, words([500, 1000]))
        record(0x02FC, words([0]) + colorRef(255, 0, 0) + words([0]))
        record(0x012D, words([0]))
        record(0x02FA, words([0, 10, 0]) + colorRef(0, 0, 255))
        record(0x012D, words([1]))
        record(0x041B, words([300, 500, 100, 100]))
        record(0x012D, words([0x8005]))
        record(0x0324, words([3, 0, 0, 1000, 500, 0, 500]))
        record(0x0201, colorRef(255, 255, 0))
        record(0x0209, colorRef(0, 128, 0))
        record(0x02FB, words([-100 & 0xFFFF, 0, 0, 0, 700]) + [0, 0, 0, UInt8(charset)] + [0, 0, 0, 0] + Array("Gulim".utf8))
        record(0x012D, words([2]))
        record(0x0A32, words([350, 200, 4, 0x0002, 200, 340, 400, 420]) + text)
        record(0x02FB, words([60, 0, 0, 0, 400]) + [1, 0, 0, 0] + [0, 0, 0, 0] + Array("Arial".utf8))
        record(0x012D, words([3]))
        record(0x0A32, words([20, 20, 7, 0]) + Array("Revenue".utf8))
        record(0x012D, words([0x8006]))
        record(0x0214, words([0, 0]))
        record(0x0213, words([250, 500]))
        record(0x0127, words([-1 & 0xFFFF]))
        record(0x020C, words([50, 100]))
        record(0x012D, words([0]))
        record(0x041B, words([50, 100, 40, 80]))
        record(0x0000, [])
        let body = records.flatMap { $0 }
        let total = (18 + body.count) / 2
        let header = words([1, 9, 0x0300, total & 0xFFFF, total >> 16, 4, 64, 0, 0])
        return HWPDocumentMetafile(data: Data(header + body), widthLogical: 1000, heightLogical: 500)
    }
}
