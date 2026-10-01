import XCTest
import UIKit
@testable import shortcuts_example

@MainActor
final class CameraControlLayoutTests: XCTestCase {
    func testCollapsedSettingsDoesNotStretchInEitherOrientation() throws {
        for size in [CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834)] {
            let controller = MagnifierViewController()
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.viewDidLayoutSubviews()
            controller.view.layoutIfNeeded()
            let settings = try XCTUnwrap(tiles(in: controller).first { $0.systemImage == "chevron.up" })
            XCTAssertEqual(settings.bounds.height, settings.intrinsicContentSize.height, accuracy: 0.5)
            XCTAssertLessThan(settings.bounds.height, 120)
            XCTAssertEqual(settings.convert(settings.bounds, to: controller.view).maxX, size.width - 14, accuracy: 0.5)
        }
    }

    func testExpandedControlsFitTheirLabelsAndCollapseBackToNaturalHeight() throws {
        let controller = MagnifierViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
        controller.viewDidLayoutSubviews()
        controller.view.layoutIfNeeded()
        let settings = try XCTUnwrap(tiles(in: controller).first { $0.systemImage == "chevron.up" })
        let collapsedHeight = settings.bounds.height
        settings.sendActions(for: .touchUpInside)
        controller.view.layoutIfNeeded()
        for tile in tiles(in: controller) {
            XCTAssertEqual(tile.bounds.height, tile.intrinsicContentSize.height, accuracy: 0.5)
            for label in labels(in: tile) where !label.isHidden {
                let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, needed.height, label.text ?? "")
            }
        }
        settings.sendActions(for: .touchUpInside)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(settings.bounds.height, collapsedHeight, accuracy: 0.5)
    }

    private func tiles(in controller: MagnifierViewController) -> [VisionCraftCameraControlTile] {
        (controller.view.accessibilityElements ?? []).compactMap { $0 as? VisionCraftCameraControlTile }
    }

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { child in
            (child as? UILabel).map { [$0] } ?? labels(in: child)
        }
    }
}
