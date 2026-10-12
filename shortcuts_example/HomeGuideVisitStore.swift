import Foundation

/// 홈 방문 횟수는 안내가 아이콘으로 바뀌는 5회까지만 저장한다.
enum HomeGuideVisitStore {
    static let storageKey = "visioncraft.home.guideVisitCount.v1"
    static let iconVisitThreshold = 5

    @discardableResult
    static func recordVisit(defaults: UserDefaults = .standard) -> Int {
        let count = min(iconVisitThreshold, max(0, defaults.integer(forKey: storageKey)))
        let next = min(iconVisitThreshold, count + 1)
        defaults.set(next, forKey: storageKey)
        return next
    }
}
