import Foundation
import Photos
import UIKit

nonisolated enum MagnifierPhotoCaptureError:
    LocalizedError,
    Equatable
{
    case encodingFailed
    case photoLibraryPermissionDenied

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return AppLocalization.string(
                "촬영한 사진을 JPEG로 만들 수 없습니다."
            )
        case .photoLibraryPermissionDenied:
            return AppLocalization.string(
                "사진 보관함 추가 권한이 없습니다. Files 저장을 이용해 주세요."
            )
        }
    }
}

nonisolated enum MagnifierPhotoNaming {
    static func filename(
        for date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(
            identifier: .gregorian
        )
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone = timeZone
        formatter.dateFormat =
            "yyyy-MM-dd-HH-mm-ss-SSS"
        return "VisionCraft-"
            + formatter.string(from: date)
            + ".jpg"
    }
}

@MainActor
struct MagnifierPhotoCapture {
    let filename: String
    let jpegData: Data

    init(
        image: UIImage,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws {
        guard let data = image.jpegData(
            compressionQuality: 0.95
        ) else {
            throw MagnifierPhotoCaptureError
                .encodingFailed
        }
        filename =
            MagnifierPhotoNaming.filename(
                for: date,
                timeZone: timeZone
            )
        jpegData = data
    }
}

@MainActor
final class MagnifierPhotoSaveService {
    private let fileManager: FileManager
    private let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory =
            temporaryDirectory
                .appendingPathComponent(
                    "VisionCraftCameraExports",
                    isDirectory: true
                )
    }

    func saveToPhotoLibrary(
        _ capture: MagnifierPhotoCapture
    ) async throws {
        let status = await authorizationStatus()
        guard status == .authorized
                || status == .limited else {
            throw MagnifierPhotoCaptureError
                .photoLibraryPermissionDenied
        }

        try await PHPhotoLibrary.shared()
            .performChanges {
                let request =
                    PHAssetCreationRequest
                    .forAsset()
                let options =
                    PHAssetResourceCreationOptions()
                options.originalFilename =
                    capture.filename
                request.addResource(
                    with: .photo,
                    data: capture.jpegData,
                    options: options
                )
            }
    }

    func makeTemporaryExportURL(
        for capture: MagnifierPhotoCapture
    ) throws -> URL {
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        var destination =
            temporaryDirectory
                .appendingPathComponent(
                    capture.filename
                )
        if fileManager.fileExists(
            atPath: destination.path
        ) {
            destination =
                temporaryDirectory
                    .appendingPathComponent(
                        "VisionCraft-"
                            + UUID()
                                .uuidString
                                .lowercased()
                            + ".jpg"
                    )
        }
        try capture.jpegData.write(
            to: destination,
            options: .atomic
        )
        return destination
    }

    func removeTemporaryExport(
        at url: URL?
    ) {
        guard let url else {
            return
        }
        let root =
            temporaryDirectory
                .standardizedFileURL
                .path
        let target =
            url.standardizedFileURL.path
        guard target.hasPrefix(
            root + "/"
        ) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }

    private func authorizationStatus()
        async -> PHAuthorizationStatus
    {
        let status =
            PHPhotoLibrary.authorizationStatus(
                for: .addOnly
            )
        guard status == .notDetermined else {
            return status
        }
        return await PHPhotoLibrary
            .requestAuthorization(
                for: .addOnly
            )
    }
}
