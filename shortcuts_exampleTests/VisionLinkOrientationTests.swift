import XCTest
import CoreVideo
@preconcurrency import StreamWebRTC
@testable import shortcuts_example

@MainActor final class VisionLinkOrientationTests: XCTestCase {
    private func frame(_ rotation: RTCVideoRotation, timestamp: Int64) throws -> RTCVideoFrame {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 80, 40, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        let bytes = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<40 { for x in 0..<80 {
            let offset = y * stride + x * 4
            bytes[offset] = y < 20 ? 0 : 255
            bytes[offset + 1] = x < 40 ? 0 : 255
            bytes[offset + 2] = y < 20 ? 255 : 0
            bytes[offset + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        return RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixel), rotation: rotation, timeStampNs: timestamp)
    }

    func testReadingSamplerAppliesEachFrameRotationOnce() async throws {
        var sizes: [CGSize] = []
        for (index, rotation) in [RTCVideoRotation._0, ._90, ._180, ._270].enumerated() {
            let ready = expectation(description: "rotation \(rotation.rawValue)")
            let sampler = VisionLinkVideoFrameSampler(frameHandler: {}, handler: { result in
                switch result {
                case .success(let image): sizes.append(CGSize(width: image.width, height: image.height))
                case .failure(let error): XCTFail("\(error)")
                }
                ready.fulfill()
            })
            sampler.requestFrame()
            sampler.renderFrame(try frame(rotation, timestamp: Int64(index + 1) * 1_000_000_000))
            await fulfillment(of: [ready], timeout: 5)
        }
        XCTAssertEqual(sizes, [CGSize(width: 80, height: 40), CGSize(width: 40, height: 80),
                               CGSize(width: 80, height: 40), CGSize(width: 40, height: 80)])
    }

}
