import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

/// `AppHomeRoot` puts `HomeImportRequestPresenter` around both homes, so the voice action's file import and
/// the remote's / help guide's text-source request work without `HomeView` (the widget launcher has none).
/// Here the presenter wraps a stand-in home and the requests go through `AppRouter` as the app sends them.
@MainActor
final class HomeImportRequestPresenterTests: XCTestCase {
    private var window: UIWindow?
    private var previousLanguage: String?
    private var accessibilityWasEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        UserDefaults.standard.set(AppLanguage.korean.rawValue, forKey: AppLanguage.preferenceKey)
        accessibilityWasEnabled = InProcessAccessibility.isEnabled
        InProcessAccessibility.setEnabled(true)
    }

    override func tearDown() async throws {
        if let presented = window?.rootViewController?.presentedViewController {
            await withCheckedContinuation { done in presented.dismiss(animated: false) { done.resume() } }
        }
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        InProcessAccessibility.setEnabled(accessibilityWasEnabled)
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
        }
        try await super.tearDown()
    }

    func testTextSourceRequestShowsTheImportDialogOverAnyHome() async throws {
        let router = AppRouter()
        let window = host(router)
        _ = try await element(in: window) { $0.accessibilityLabel == "대체 홈" }

        router.requestTextSource()
        _ = try await element(in: window) { self.matches($0.accessibilityLabel ?? "", "이미지") }
        _ = try await element(in: window) { self.matches($0.accessibilityLabel ?? "", "문서") }
        XCTAssertFalse(elements(in: window).contains { $0.accessibilityLabel == "대체 홈" },
            "the home under the dialog is hidden from VoiceOver")

        // 닫기 closes it and the home reads again; a second request opens it again.
        let close = try await element(in: window) {
            $0.accessibilityTraits.contains(.button) && self.matches($0.accessibilityLabel ?? "", "닫기")
        }
        XCTAssertTrue(close.accessibilityActivate())
        _ = try await element(in: window) { $0.accessibilityLabel == "대체 홈" }
        router.requestTextSource()
        _ = try await element(in: window) { self.matches($0.accessibilityLabel ?? "", "문서") }
    }

    func testFileImportRequestPresentsTheDocumentPicker() async throws {
        let router = AppRouter()
        let window = host(router)
        _ = try await element(in: window) { $0.accessibilityLabel == "대체 홈" }

        router.requestFileImport()
        let deadline = Date().addingTimeInterval(5)
        while window.rootViewController?.presentedViewController == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let presented = try XCTUnwrap(window.rootViewController?.presentedViewController, "no file importer")
        XCTAssertTrue(presented is UIDocumentPickerViewController, "\(type(of: presented))")
    }

    // MARK: - Hosting

    private func host(_ router: AppRouter) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.windowLevel = .normal + 10
        let home = Text(verbatim: "대체 홈")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HomeImportRequestPresenter())
            .environmentObject(router)
        window.rootViewController = UIHostingController(rootView: home)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        self.window = window
        return window
    }

    private func matches(_ text: String, _ key: String) -> Bool {
        text == key || text == AppLocalization.string(key)
    }

    private func element(in window: UIWindow, _ predicate: (NSObject) -> Bool) async throws -> NSObject {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let match = elements(in: window).first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Accessibility element not found: \(elements(in: window).map { $0.accessibilityLabel ?? "" })")
        throw CancellationError()
    }

    /// VoiceOver's elements: a container's accessibilityElements replace its subviews, and an element is a leaf.
    private func elements(in window: UIWindow) -> [NSObject] {
        var found: [NSObject] = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 120 else { return }
            if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
            if object.accessibilityElementsHidden { return }
            if object.isAccessibilityElement {
                found.append(object)
                return
            }
            if let list = object.accessibilityElements {
                list.compactMap { $0 as? NSObject }.forEach { visit($0, depth: depth + 1) }
            } else if let view = object as? UIView {
                view.subviews.forEach { visit($0, depth: depth + 1) }
            }
        }
        visit(window, depth: 0)
        return found
    }
}

/// The in-process accessibility flag XCUITest and VoiceOver turn on; SwiftUI builds the full accessibility
/// tree of nested hosting views only while it is on.
private enum InProcessAccessibility {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void
    private static let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)

    static var isEnabled: Bool {
        guard let handle, let symbol = dlsym(handle, "_AXSApplicationAccessibilityEnabled") else { return false }
        return unsafeBitCast(symbol, to: Getter.self)()
    }

    static func setEnabled(_ enabled: Bool) {
        guard let handle else { return }
        for name in ["_AXSApplicationAccessibilitySetEnabled", "_AXSSetAutomationEnabled"] {
            if let symbol = dlsym(handle, name) { unsafeBitCast(symbol, to: Setter.self)(enabled) }
        }
    }
}
