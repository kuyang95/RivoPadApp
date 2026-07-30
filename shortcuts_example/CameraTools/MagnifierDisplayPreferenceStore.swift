import Foundation

@MainActor
final class MagnifierDisplayPreferenceStore {
    private enum Key {
        static let colorIndex =
            "camera.display.colorIndex.v1"
        static let colorInverted =
            "camera.display.colorInverted.v1"
        static let threshold =
            "camera.display.threshold.v1"
    }

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
    }

    func load(
        applyingTo current:
            MagnifierDisplayAdjustment,
        colorCount: Int =
            LocalDocumentColorTheme.all.count
    ) -> MagnifierDisplayAdjustment {
        var restored = current

        if colorCount > 0,
           let storedIndex =
                defaults.object(
                    forKey: Key.colorIndex
                ) as? NSNumber {
            restored.colorIndex = min(
                max(storedIndex.intValue, 0),
                colorCount - 1
            )
            restored.isInverted =
                defaults.bool(
                    forKey:
                        Key.colorInverted
                )
        }

        if let storedThreshold =
                defaults.object(
                    forKey: Key.threshold
                ) as? NSNumber {
            let value =
                CGFloat(
                    storedThreshold.doubleValue
                )
            if value.isFinite {
                restored.threshold = min(
                    max(value, 0),
                    1.05
                )
            }
        }

        return restored
    }

    func saveColor(
        from adjustment:
            MagnifierDisplayAdjustment
    ) {
        guard let colorIndex =
                adjustment.colorIndex else {
            return
        }
        defaults.set(
            colorIndex,
            forKey: Key.colorIndex
        )
        defaults.set(
            adjustment.isInverted,
            forKey: Key.colorInverted
        )
    }

    func saveThreshold(
        from adjustment:
            MagnifierDisplayAdjustment
    ) {
        defaults.set(
            Double(adjustment.threshold),
            forKey: Key.threshold
        )
    }

    func saveInversion(
        from adjustment:
            MagnifierDisplayAdjustment
    ) {
        defaults.set(
            adjustment.isInverted,
            forKey: Key.colorInverted
        )
    }

    func reset() {
        defaults.removeObject(
            forKey: Key.colorIndex
        )
        defaults.removeObject(
            forKey: Key.colorInverted
        )
        defaults.removeObject(
            forKey: Key.threshold
        )
    }
}
