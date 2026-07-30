@preconcurrency import CoreBluetooth
import Combine
import Foundation

nonisolated enum RivoConnectionDiagnosticLevel:
    String,
    Codable,
    Equatable,
    Sendable
{
    case info
    case success
    case warning
    case failure

    var title: String {
        switch self {
        case .info:
            return "정보"
        case .success:
            return "완료"
        case .warning:
            return "주의"
        case .failure:
            return "실패"
        }
    }
}

nonisolated enum RivoConnectionDiagnosticStage:
    String,
    Codable,
    Equatable,
    Sendable
{
    case bluetooth
    case scanning
    case connecting
    case services
    case characteristics
    case notifications
    case ready
    case disconnected
    case reconnecting
    case packets
    case timeSync

    var title: String {
        switch self {
        case .bluetooth:
            return "Bluetooth"
        case .scanning:
            return "검색"
        case .connecting:
            return "연결"
        case .services:
            return "서비스"
        case .characteristics:
            return "특성"
        case .notifications:
            return "알림"
        case .ready:
            return "준비"
        case .disconnected:
            return "연결 해제"
        case .reconnecting:
            return "재연결"
        case .packets:
            return "패킷"
        case .timeSync:
            return "시간 동기화"
        }
    }
}

nonisolated struct RivoConnectionDiagnostic:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    let id: UUID
    let recordedAt: Date
    let level: RivoConnectionDiagnosticLevel
    let stage: RivoConnectionDiagnosticStage
    let message: String
}

nonisolated enum RivoBluetoothState: Equatable, Sendable {
    case inactive
    case preparing
    case scanning
    case connecting(String)
    case discovering(String)
    case ready(String)
    case bluetoothOff
    case permissionDenied
    case unsupported
    case disconnected
    case failed(String)

    var title: String {
        switch self {
        case .inactive:
            return "리모컨 검색 전"
        case .preparing:
            return "Bluetooth 준비 중"
        case .scanning:
            return "Rivo 리모컨 검색 중"
        case .connecting(let name):
            return "\(name) 연결 중"
        case .discovering(let name):
            return "\(name) 서비스 확인 중"
        case .ready(let name):
            return "\(name) 연결됨"
        case .bluetoothOff:
            return "Bluetooth가 꺼져 있습니다"
        case .permissionDenied:
            return "Bluetooth 권한이 필요합니다"
        case .unsupported:
            return "Bluetooth LE를 지원하지 않습니다"
        case .disconnected:
            return "리모컨 연결 끊김"
        case .failed(let message):
            return message
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

nonisolated enum RivoTimeSyncState:
    Equatable,
    Sendable
{
    case idle
    case sending
    case sent(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "연결 후 자동으로 맞춥니다."
        case .sending:
            return "현재 시간을 보내는 중"
        case .sent:
            return "현재 시간을 전송했습니다."
        case .failed(let message):
            return message
        }
    }
}

nonisolated struct RivoDiscoveredDevice:
    Identifiable,
    Equatable,
    Sendable
{
    let id: UUID
    let name: String
    let type: RivoDeviceType
    let discoverySource: RivoDiscoverySource
    let signalStrength: Int

    var signalDescription: String {
        switch signalStrength {
        case -55 ... 0:
            return "매우 강함"
        case -70 ..< -55:
            return "강함"
        case -85 ..< -70:
            return "보통"
        default:
            return "약함"
        }
    }
}

nonisolated struct RivoRemoteEvent:
    Identifiable,
    Equatable,
    Sendable
{
    let id: UUID
    let input: RivoRemoteInput
    let receivedAt: Date
    let packetHex: String
}

@MainActor
final class RivoRemoteManager:
    NSObject,
    ObservableObject,
    @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate
{
    private enum DefaultsKey {
        static let peripheralIdentifier =
            "rivo.remote.peripheralIdentifier"
        static let deviceType = "rivo.remote.deviceType"
        static let connectionDiagnostics =
            "rivo.remote.connectionDiagnostics"
    }

    private static let uartWriteCharacteristic = CBUUID(
        string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"
    )
    private static let uartNotifyCharacteristic = CBUUID(
        string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    )
    private static let restorationIdentifier =
        "com.rivo.shortcuts-example.rivo-central"

    @Published private(set) var state: RivoBluetoothState =
        .inactive
    @Published private(set) var discoveredDevices:
        [RivoDiscoveredDevice] = []
    @Published private(set) var recentEvents:
        [RivoRemoteEvent] = []
    @Published private(set) var latestInputBatch:
        [RivoRemoteInput] = []
    @Published private(set) var eventSequence = 0
    @Published private(set) var invalidPacketCount = 0
    @Published private(set) var connectedDeviceType:
        RivoDeviceType?
    @Published private(set) var timeSyncState:
        RivoTimeSyncState = .idle
    @Published private(set) var connectionDiagnostics:
        [RivoConnectionDiagnostic] = []

    private let defaults: UserDefaults
    private var centralManager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveredTypes: [UUID: RivoDeviceType] = [:]
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var assembler = RivoPacketAssembler()
    private var wantsScan = false
    private var shouldReconnect = false
    private var connectionTimeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var periodicTimeSyncTask:
        Task<Void, Never>?
    private var automaticTimeSyncPeripheralIdentifier:
        UUID?
    private var pendingCharacteristicDiscoveryCount = 0
    private var didFinishCharacteristicDiscovery = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        restoreConnectionDiagnostics()

        if savedPeripheralIdentifier != nil {
            shouldReconnect = true
            recordDiagnostic(
                .info,
                stage: .reconnecting,
                message: "저장된 Rivo 자동 연결을 준비합니다."
            )
            prepareCentralManager()
        }
    }

    deinit {
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()
        periodicTimeSyncTask?.cancel()
    }

    var connectedDeviceName: String? {
        activePeripheral?.name
    }

    var lastInput: RivoRemoteInput? {
        recentEvents.first?.input
    }

    func activateAndScan() {
        guard !state.isReady else {
            return
        }
        wantsScan = true
        shouldReconnect = true
        prepareCentralManager()
        guard let centralManager,
              centralManager.state == .poweredOn else {
            return
        }
        if savedPeripheralIdentifier != nil {
            attemptSavedConnection()
        } else {
            startScanning()
        }
    }

    func startScanning() {
        prepareCentralManager()
        guard let centralManager else {
            return
        }
        wantsScan = true
        shouldReconnect = true

        guard centralManager.state == .poweredOn else {
            updateState(for: centralManager.state)
            return
        }
        guard !state.isReady else {
            return
        }

        centralManager.stopScan()
        discoveredDevices = []
        peripherals = [:]
        discoveredTypes = [:]
        state = .scanning
        recordDiagnostic(
            .info,
            stage: .scanning,
            message:
                "Rivo 서비스 UUID와 기기 이름을 함께 검색합니다."
        )
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey:
                    false
            ]
        )
    }

    func stopScanning() {
        wantsScan = false
        centralManager?.stopScan()
        if case .scanning = state {
            state = .inactive
            recordDiagnostic(
                .info,
                stage: .scanning,
                message: "사용자가 검색을 중지했습니다."
            )
        }
    }

    func connect(to device: RivoDiscoveredDevice) {
        guard let peripheral = peripherals[device.id],
              let centralManager else {
            let message =
                "검색 결과가 만료되었습니다. 다시 검색해 주세요."
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .connecting,
                message: message
            )
            return
        }
        discoveredTypes[device.id] = device.type
        connect(peripheral, using: centralManager)
    }

    func disconnect() {
        wantsScan = false
        shouldReconnect = false
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier =
            nil
        timeSyncState = .idle
        guard let activePeripheral else {
            state = .disconnected
            recordDiagnostic(
                .info,
                stage: .disconnected,
                message: "연결할 Rivo가 없습니다."
            )
            return
        }
        centralManager?.cancelPeripheralConnection(
            activePeripheral
        )
        state = .disconnected
        recordDiagnostic(
            .info,
            stage: .disconnected,
            message: "사용자가 Rivo 연결을 끊었습니다."
        )
    }

    func forgetDevice() {
        disconnect()
        defaults.removeObject(
            forKey: DefaultsKey.peripheralIdentifier
        )
        defaults.removeObject(
            forKey: DefaultsKey.deviceType
        )
        connectedDeviceType = nil
        activePeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        timeSyncState = .idle
        recentEvents = []
        latestInputBatch = []
        state = .inactive
    }

    func clearEventHistory() {
        recentEvents = []
        latestInputBatch = []
        invalidPacketCount = 0
    }

    func clearConnectionDiagnostics() {
        connectionDiagnostics = []
        defaults.removeObject(
            forKey: DefaultsKey.connectionDiagnostics
        )
    }

    func syncTime() {
        guard state.isReady,
              let peripheral = activePeripheral,
              let characteristic =
                writeCharacteristic else {
            let message =
                "Rivo가 연결된 뒤 다시 시도해 주세요."
            timeSyncState = .failed(message)
            recordDiagnostic(
                .warning,
                stage: .timeSync,
                message: message
            )
            return
        }
        let writeType:
            CBCharacteristicWriteType
        if characteristic.properties
            .contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if characteristic.properties
            .contains(.write) {
            writeType = .withResponse
        } else {
            let message =
                "이 Rivo의 시간 쓰기 특성을 지원하지 않습니다."
            timeSyncState = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .timeSync,
                message: message
            )
            return
        }

        timeSyncState = .sending
        let packet =
            RivoTimeSyncPacketEncoder.packet(
                for: Date()
            )
        peripheral.writeValue(
            packet,
            for: characteristic,
            type: writeType
        )
        if writeType == .withoutResponse {
            noteTimePacketSent()
        }
    }

    private var savedPeripheralIdentifier: UUID? {
        guard let rawValue = defaults.string(
            forKey: DefaultsKey.peripheralIdentifier
        ) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private var savedDeviceType: RivoDeviceType? {
        guard let rawValue = defaults.string(
            forKey: DefaultsKey.deviceType
        ) else {
            return nil
        }
        return RivoDeviceType(rawValue: rawValue)
    }

    private func prepareCentralManager() {
        guard centralManager == nil else {
            return
        }
        state = .preparing
        recordDiagnostic(
            .info,
            stage: .bluetooth,
            message: "Bluetooth 중앙 장치를 준비합니다."
        )
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey:
                    Self.restorationIdentifier,
                CBCentralManagerOptionShowPowerAlertKey:
                    true
            ]
        )
    }

    private func attemptSavedConnection() {
        guard let centralManager,
              centralManager.state == .poweredOn,
              let identifier = savedPeripheralIdentifier else {
            startScanning()
            return
        }

        let restored = centralManager.retrievePeripherals(
            withIdentifiers: [identifier]
        )
        guard let peripheral = restored.first else {
            recordDiagnostic(
                .warning,
                stage: .reconnecting,
                message:
                    "저장된 Rivo를 찾지 못해 주변 검색으로 전환합니다."
            )
            startScanning()
            return
        }
        if let savedDeviceType {
            discoveredTypes[identifier] = savedDeviceType
        }
        peripherals[identifier] = peripheral
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message: "저장된 Rivo에 다시 연결합니다."
        )
        connect(peripheral, using: centralManager)
    }

    private func connect(
        _ peripheral: CBPeripheral,
        using centralManager: CBCentralManager
    ) {
        centralManager.stopScan()
        wantsScan = false
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()

        if let activePeripheral,
           activePeripheral.identifier != peripheral.identifier {
            centralManager.cancelPeripheralConnection(
                activePeripheral
            )
        }

        self.activePeripheral = peripheral
        peripheral.delegate = self
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingCharacteristicDiscoveryCount = 0
        didFinishCharacteristicDiscovery = false
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier =
            nil
        timeSyncState = .idle
        assembler.reset()
        state = .connecting(displayName(for: peripheral))
        recordDiagnostic(
            .info,
            stage: .connecting,
            message:
                "\(displayName(for: peripheral)) 연결을 시작합니다."
        )
        centralManager.connect(peripheral)
        scheduleConnectionTimeout(for: peripheral.identifier)
    }

    private func scheduleConnectionTimeout(
        for identifier: UUID
    ) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: 10_000_000_000
            )
            guard !Task.isCancelled,
                  let self,
                  self.activePeripheral?.identifier
                    == identifier,
                  !self.state.isReady else {
                return
            }
            if let peripheral = self.activePeripheral {
                self.centralManager?
                    .cancelPeripheralConnection(peripheral)
            }
            let message =
                "Rivo 연결 또는 준비 시간이 10초를 초과했습니다."
            self.state = .failed(message)
            self.recordDiagnostic(
                .failure,
                stage: self.connectionTimeoutStage,
                message: message
            )
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else {
            return
        }
        reconnectTask?.cancel()
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message: "1초 뒤 Rivo 연결을 다시 시도합니다."
        )
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: 1_000_000_000
            )
            guard !Task.isCancelled,
                  let self,
                  self.shouldReconnect else {
                return
            }
            if self.savedPeripheralIdentifier != nil {
                self.attemptSavedConnection()
            } else {
                self.startScanning()
            }
        }
    }

    private func displayName(
        for peripheral: CBPeripheral
    ) -> String {
        if let name = peripheral.name,
           !name.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            return name
        }
        if let type = discoveredTypes[peripheral.identifier]
            ?? savedDeviceType {
            return type.title
        }
        return "Rivo 리모컨"
    }

    private func deviceType(
        from services: [CBUUID]
    ) -> RivoDeviceType? {
        services.lazy.compactMap {
            RivoDeviceType.from(
                serviceUUID: $0.uuidString
            )
        }
        .first
    }

    private func markReadyIfPossible() {
        guard !state.isReady,
              let peripheral = activePeripheral,
              writeCharacteristic != nil,
              let notifyCharacteristic,
              notifyCharacteristic.isNotifying,
              let type = discoveredTypes[
                  peripheral.identifier
              ] ?? savedDeviceType else {
            return
        }

        connectionTimeoutTask?.cancel()
        connectedDeviceType = type
        defaults.set(
            peripheral.identifier.uuidString,
            forKey: DefaultsKey.peripheralIdentifier
        )
        defaults.set(
            type.rawValue,
            forKey: DefaultsKey.deviceType
        )
        state = .ready(displayName(for: peripheral))
        recordDiagnostic(
            .success,
            stage: .ready,
            message:
                "\(displayName(for: peripheral)) 버튼 수신 준비가 끝났습니다."
        )
        if automaticTimeSyncPeripheralIdentifier
            != peripheral.identifier {
            automaticTimeSyncPeripheralIdentifier =
                peripheral.identifier
            syncTime()
        }
    }

    private func noteTimePacketSent() {
        timeSyncState = .sent(Date())
        recordDiagnostic(
            .success,
            stage: .timeSync,
            message: "Rivo에 iPad 현재 시간을 전송했습니다."
        )
        schedulePeriodicTimeSync()
    }

    private func schedulePeriodicTimeSync() {
        periodicTimeSyncTask?.cancel()
        periodicTimeSyncTask =
            Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds:
                        43_200_000_000_000
                )
                guard !Task.isCancelled,
                      let self,
                      self.state.isReady else {
                    return
                }
                self.syncTime()
            }
    }

    private func restoreConnectionDiagnostics() {
        guard let data = defaults.data(
            forKey: DefaultsKey.connectionDiagnostics
        ),
        let decoded = try? JSONDecoder().decode(
            [RivoConnectionDiagnostic].self,
            from: data
        ) else {
            return
        }
        connectionDiagnostics = Array(
            decoded.prefix(80)
        )
    }

    private func recordDiagnostic(
        _ level: RivoConnectionDiagnosticLevel,
        stage: RivoConnectionDiagnosticStage,
        message: String
    ) {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return
        }
        connectionDiagnostics.insert(
            RivoConnectionDiagnostic(
                id: UUID(),
                recordedAt: Date(),
                level: level,
                stage: stage,
                message: String(trimmed.prefix(300))
            ),
            at: 0
        )
        if connectionDiagnostics.count > 80 {
            connectionDiagnostics.removeLast(
                connectionDiagnostics.count - 80
            )
        }
        if let data = try? JSONEncoder().encode(
            connectionDiagnostics
        ) {
            defaults.set(
                data,
                forKey: DefaultsKey.connectionDiagnostics
            )
        }
    }

    private func connectionErrorMessage(
        _ error: Error?,
        fallback: String
    ) -> String {
        guard let error else {
            return fallback
        }
        return "\(fallback): \(error.localizedDescription)"
    }

    private func finishCharacteristicDiscovery(
        for peripheral: CBPeripheral
    ) {
        guard pendingCharacteristicDiscoveryCount == 0,
              !didFinishCharacteristicDiscovery else {
            return
        }
        didFinishCharacteristicDiscovery = true
        var missing: [String] = []
        if writeCharacteristic == nil {
            missing.append("UART 쓰기")
        }
        if notifyCharacteristic == nil {
            missing.append("UART 알림")
        }
        guard missing.isEmpty else {
            let message =
                "필수 \(missing.joined(separator: "·")) 특성을 찾지 못했습니다."
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .characteristics,
                message: message
            )
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        recordDiagnostic(
            .success,
            stage: .characteristics,
            message: "UART 쓰기·알림 특성을 확인했습니다."
        )
        markReadyIfPossible()
    }

    private var connectionTimeoutStage:
        RivoConnectionDiagnosticStage
    {
        if case .connecting = state {
            return .connecting
        }
        if pendingCharacteristicDiscoveryCount > 0 {
            return .characteristics
        }
        if didFinishCharacteristicDiscovery,
           let notifyCharacteristic,
           !notifyCharacteristic.isNotifying {
            return .notifications
        }
        if writeCharacteristic == nil
            || notifyCharacteristic == nil {
            return .services
        }
        return .connecting
    }

    private func updateState(
        for managerState: CBManagerState
    ) {
        switch managerState {
        case .poweredOn:
            recordDiagnostic(
                .success,
                stage: .bluetooth,
                message: "Bluetooth를 사용할 수 있습니다."
            )
            if shouldReconnect,
               savedPeripheralIdentifier != nil {
                attemptSavedConnection()
            } else if wantsScan {
                startScanning()
            } else {
                state = .inactive
            }
        case .poweredOff:
            state = .bluetoothOff
            recordDiagnostic(
                .warning,
                stage: .bluetooth,
                message: "Bluetooth가 꺼져 있습니다."
            )
        case .unauthorized:
            state = .permissionDenied
            recordDiagnostic(
                .failure,
                stage: .bluetooth,
                message: "Bluetooth 권한이 허용되지 않았습니다."
            )
        case .unsupported:
            state = .unsupported
            recordDiagnostic(
                .failure,
                stage: .bluetooth,
                message: "이 기기는 Bluetooth LE를 지원하지 않습니다."
            )
        case .resetting:
            state = .preparing
            recordDiagnostic(
                .warning,
                stage: .bluetooth,
                message: "Bluetooth가 재설정되고 있습니다."
            )
        case .unknown:
            state = .preparing
            recordDiagnostic(
                .info,
                stage: .bluetooth,
                message: "Bluetooth 상태를 확인하고 있습니다."
            )
        @unknown default:
            let message =
                "알 수 없는 Bluetooth 상태입니다."
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .bluetooth,
                message: message
            )
        }
    }

    func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {
        updateState(for: central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard let restored = dict[
            CBCentralManagerRestoredStatePeripheralsKey
        ] as? [CBPeripheral],
              let peripheral = restored.first else {
            return
        }
        shouldReconnect = true
        activePeripheral = peripheral
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message:
                "iPadOS가 복원한 Rivo 연결을 이어받았습니다."
        )

        if peripheral.state == .connected {
            state = .discovering(
                displayName(for: peripheral)
            )
            peripheral.discoverServices(nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedServices = advertisementData[
            CBAdvertisementDataServiceUUIDsKey
        ] as? [CBUUID] ?? []
        let advertisedName = advertisementData[
            CBAdvertisementDataLocalNameKey
        ] as? String
        let savedTypeForPeripheral =
            savedPeripheralIdentifier
                == peripheral.identifier
                ? savedDeviceType
                : nil
        guard let match =
                RivoAdvertisementClassifier.match(
                    serviceUUIDs:
                        advertisedServices.map(\.uuidString),
                    advertisedName: advertisedName,
                    peripheralName: peripheral.name,
                    savedType: savedTypeForPeripheral
                ) else {
            return
        }
        let type = match.type
        let name = advertisedName
            ?? peripheral.name
            ?? type.title
        let device = RivoDiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            type: type,
            discoverySource: match.source,
            signalStrength: RSSI.intValue
        )
        peripherals[peripheral.identifier] = peripheral
        discoveredTypes[peripheral.identifier] = type

        if let index = discoveredDevices.firstIndex(
            where: { $0.id == device.id }
        ) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            recordDiagnostic(
                .success,
                stage: .scanning,
                message:
                    "\(name)을 \(match.source.title)으로 찾았습니다."
            )
        }
        discoveredDevices.sort {
            $0.signalStrength > $1.signalStrength
        }

        if savedPeripheralIdentifier
            == peripheral.identifier {
            connect(peripheral, using: central)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        activePeripheral = peripheral
        peripheral.delegate = self
        state = .discovering(displayName(for: peripheral))
        recordDiagnostic(
            .success,
            stage: .connecting,
            message:
                "\(displayName(for: peripheral)) BLE 연결에 성공했습니다."
        )
        recordDiagnostic(
            .info,
            stage: .services,
            message: "GATT 서비스를 확인합니다."
        )
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionTimeoutTask?.cancel()
        let message = connectionErrorMessage(
            error,
            fallback: "Rivo 리모컨에 연결하지 못했습니다."
        )
        state = .failed(message)
        recordDiagnostic(
            .failure,
            stage: .connecting,
            message: message
        )
        scheduleReconnect()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionTimeoutTask?.cancel()
        writeCharacteristic = nil
        notifyCharacteristic = nil
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier =
            nil
        timeSyncState = .idle
        assembler.reset()
        pendingCharacteristicDiscoveryCount = 0
        didFinishCharacteristicDiscovery = false
        if !shouldReconnect,
           savedPeripheralIdentifier == nil {
            state = .inactive
        } else {
            state = error.map {
                .failed($0.localizedDescription)
            } ?? .disconnected
        }
        recordDiagnostic(
            error == nil ? .info : .failure,
            stage: .disconnected,
            message: connectionErrorMessage(
                error,
                fallback:
                    "\(displayName(for: peripheral)) 연결이 끊겼습니다."
            )
        )
        scheduleReconnect()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            let message = connectionErrorMessage(
                error,
                fallback: "GATT 서비스 검색에 실패했습니다."
            )
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .services,
                message: message
            )
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            let message =
                "Rivo에서 GATT 서비스를 찾지 못했습니다."
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .services,
                message: message
            )
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        if let type = deviceType(
            from: services.map(\.uuid)
        ) {
            discoveredTypes[peripheral.identifier] = type
        }
        recordDiagnostic(
            .success,
            stage: .services,
            message: "GATT 서비스 \(services.count)개를 찾았습니다."
        )
        pendingCharacteristicDiscoveryCount =
            services.count
        didFinishCharacteristicDiscovery = false
        for service in services {
            peripheral.discoverCharacteristics(
                [
                    Self.uartWriteCharacteristic,
                    Self.uartNotifyCharacteristic
                ],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        pendingCharacteristicDiscoveryCount = max(
            pendingCharacteristicDiscoveryCount - 1,
            0
        )
        if let error {
            recordDiagnostic(
                .warning,
                stage: .characteristics,
                message: connectionErrorMessage(
                    error,
                    fallback:
                        "\(service.uuid.uuidString) 특성 검색에 실패했습니다."
                )
            )
            finishCharacteristicDiscovery(
                for: peripheral
            )
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid
                == Self.uartWriteCharacteristic {
                writeCharacteristic = characteristic
            } else if characteristic.uuid
                == Self.uartNotifyCharacteristic {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(
                    true,
                    for: characteristic
                )
            }
        }
        finishCharacteristicDiscovery(for: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic:
            CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let message = connectionErrorMessage(
                error,
                fallback: "UART 알림 구독에 실패했습니다."
            )
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .notifications,
                message: message
            )
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        guard characteristic.isNotifying else {
            let message =
                "Rivo가 UART 알림 구독을 활성화하지 않았습니다."
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .notifications,
                message: message
            )
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        recordDiagnostic(
            .success,
            stage: .notifications,
            message: "UART 버튼 알림 구독을 시작했습니다."
        )
        markReadyIfPossible()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid
                == Self.uartNotifyCharacteristic,
              let value = characteristic.value else {
            if error != nil {
                invalidPacketCount += 1
                recordDiagnostic(
                    .warning,
                    stage: .packets,
                    message: connectionErrorMessage(
                        error,
                        fallback:
                            "Rivo 버튼 알림을 읽지 못했습니다."
                    )
                )
            }
            return
        }

        var parsedInputs: [RivoRemoteInput] = []
        for packet in assembler.append(value) {
            guard let input = RivoRemotePacketParser.parse(
                packet
            ) else {
                invalidPacketCount += 1
                if invalidPacketCount <= 3
                    || invalidPacketCount % 10 == 0 {
                    recordDiagnostic(
                        .warning,
                        stage: .packets,
                        message:
                            "해석하지 못한 Rivo 패킷이 \(invalidPacketCount)개입니다."
                    )
                }
                continue
            }
            recentEvents.insert(
                RivoRemoteEvent(
                    id: UUID(),
                    input: input,
                    receivedAt: Date(),
                    packetHex:
                        RivoRemotePacketParser.hex(packet)
                ),
                at: 0
            )
            parsedInputs.append(input)
            if recentEvents.count > 30 {
                recentEvents.removeLast(
                    recentEvents.count - 30
                )
            }
        }
        if !parsedInputs.isEmpty {
            latestInputBatch = parsedInputs
            eventSequence &+= 1
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid
                == Self.uartWriteCharacteristic,
              case .sending = timeSyncState else {
            return
        }
        if let error {
            let message =
                "현재 시간을 보내지 못했습니다: "
                + error.localizedDescription
            timeSyncState = .failed(message)
            recordDiagnostic(
                .warning,
                stage: .timeSync,
                message: message
            )
        } else {
            noteTimePacketSent()
        }
    }
}
