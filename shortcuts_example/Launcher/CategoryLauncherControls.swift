import SwiftUI
import UIKit

struct CategoryWidgetNavigation {
    let index: Int
    let count: Int
    let onTurn: (Int) -> Void
    let onCatalog: () -> Void
    let onEdit: () -> Void
    var onDrag: ((CGFloat) -> Void)? = nil
    var onDragEnd: ((Bool) -> Void)? = nil

}

struct CategoryWidgetPageActions: ViewModifier {
    let navigation: CategoryWidgetNavigation?

    func body(content: Content) -> some View {
        if let navigation {
            content
                .accessibilityValue(Text("\(navigation.count + 1)페이지 중 \(navigation.index + 1)페이지"))
                .accessibilityScrollAction { edge in
                    if edge == .trailing, navigation.index < navigation.count { navigation.onTurn(1) }
                    else if edge == .leading, navigation.index > 0 { navigation.onTurn(-1) }
                }
                .accessibilityActions {
                    if navigation.index > 0 { Button("이전 홈 페이지") { navigation.onTurn(-1) } }
                    if navigation.index < navigation.count { Button("다음 홈 페이지") { navigation.onTurn(1) } }
                    Button("위젯 추가", action: navigation.onEdit)
                    Button("전체 앱·기능", action: navigation.onCatalog)
                }
        } else {
            content
        }
    }
}

struct CategoryWidgetPageSwipe: ViewModifier {
    let navigation: CategoryWidgetNavigation?
    var enabled = true
    @State private var width: CGFloat = 0
    @State private var axis = 0
    @GestureState private var gestureActive = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        if axis == 0 {
                            axis = abs(value.translation.width) > abs(value.translation.height) * 1.5 ? 1 : 2
                        }
                        if axis == 1 { navigation?.onDrag?(value.translation.width) }
                    }
                    .onEnded { value in
                        if axis == 1 {
                            if let finish = navigation?.onDragEnd {
                                finish(false)
                            } else if abs(value.translation.width) >= max(64, width * 0.15) {
                                navigation?.onTurn(value.translation.width < 0 ? 1 : -1)
                            }
                        }
                        axis = 0
                    },
                including: enabled && navigation != nil ? .all : .none
            )
            .onChange(of: gestureActive) { _, active in
                if !active, axis == 1 {
                    navigation?.onDragEnd?(true)
                    axis = 0
                }
            }
    }
}

struct LauncherPosterLongPress: ViewModifier {
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    func body(content: Content) -> some View {
        if let onLongPress {
            content.launcherLongPress(onTap: onTap, onLongPress: onLongPress)
                .accessibilityAction(named: Text("위젯 추가"), onLongPress)
        } else {
            content
        }
    }
}

extension View {
    /// Physical taps and holds use an exclusive gesture. Button activation remains available to assistive input.
    func launcherLongPress(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        highPriorityGesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { result in
            switch result {
            case .first: onLongPress()
            case .second: onTap()
            }
        })
    }

    func launcherHomeSwipe(
        height: CGFloat,
        enabled: Bool = true,
        onCatalog: @escaping () -> Void,
        onTurn: ((Int) -> Void)? = nil
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 22).onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let bottom = height <= 60 ? 0 : height - min(120, height * 0.32)
                if value.startLocation.y >= bottom, dy < -44, -dy > abs(dx) * 1.5 {
                    onCatalog()
                } else if abs(dx) > max(44, abs(dy) * 1.5) {
                    onTurn?(dx < 0 ? 1 : -1)
                }
            }, including: enabled ? .all : .none
        )
    }
}
