import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum RivoWidgetConnectionKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case notConnected
    case connecting
    case connected
    case unavailable
    case failed
}

nonisolated struct RivoWidgetSnapshot:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    let schemaVersion: Int
    let kind: RivoWidgetConnectionKind
    let title: String
    let deviceName: String?
    let updatedAt: Date
}

enum RivoWidgetStatusStore {
    static let suiteName =
        "group.com.rivo.shortcuts.example"
    static let snapshotKey =
        "rivo.widget.snapshot.v1"
    static let widgetKind =
        "RivoStatusWidget"

    static func snapshot(
        for state: RivoBluetoothState,
        updatedAt: Date = Date()
    ) -> RivoWidgetSnapshot {
        let kind: RivoWidgetConnectionKind
        let deviceName: String?
        switch state {
        case .inactive:
            kind = .notConnected
            deviceName = nil
        case .preparing,
             .scanning:
            kind = .connecting
            deviceName = nil
        case .connecting(let name),
             .discovering(let name):
            kind = .connecting
            deviceName = name
        case .ready(let name):
            kind = .connected
            deviceName = name
        case .bluetoothOff,
             .permissionDenied,
             .unsupported:
            kind = .unavailable
            deviceName = nil
        case .disconnected:
            kind = .notConnected
            deviceName = nil
        case .failed:
            kind = .failed
            deviceName = nil
        }
        return RivoWidgetSnapshot(
            schemaVersion:
                RivoWidgetSnapshot.schemaVersion,
            kind: kind,
            title: String(
                state.title.prefix(120)
            ),
            deviceName: deviceName.map {
                String($0.prefix(80))
            },
            updatedAt: updatedAt
        )
    }

    static func save(
        state: RivoBluetoothState,
        updatedAt: Date = Date(),
        defaults: UserDefaults? = nil,
        reloadWidget: Bool = true
    ) {
        guard let defaults =
                defaults
                ?? UserDefaults(
                    suiteName: suiteName
                ) else {
            return
        }
        let snapshot = snapshot(
            for: state,
            updatedAt: updatedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder
            .encode(snapshot) else {
            return
        }
        defaults.set(
            data,
            forKey: snapshotKey
        )
        if reloadWidget {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(
                ofKind: widgetKind
            )
            #endif
        }
    }

    static func load(
        defaults: UserDefaults? = nil
    ) -> RivoWidgetSnapshot? {
        guard let defaults =
                defaults
                ?? UserDefaults(
                    suiteName: suiteName
                ),
              let data = defaults.data(
                  forKey: snapshotKey
              ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder
            .decode(
                RivoWidgetSnapshot.self,
                from: data
            ),
              snapshot.schemaVersion
                == RivoWidgetSnapshot
                .schemaVersion else {
            return nil
        }
        return snapshot
    }
}
