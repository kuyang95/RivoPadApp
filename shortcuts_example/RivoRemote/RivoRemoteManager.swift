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
            return AppLocalization.string("정보")
        case .success:
            return AppLocalization.string("완료")
        case .warning:
            return AppLocalization.string("주의")
        case .failure:
            return AppLocalization.string("실패")
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
            return AppLocalization.string("검색")
        case .connecting:
            return AppLocalization.string("연결")
        case .services:
            return AppLocalization.string("서비스")
        case .characteristics:
            return AppLocalization.string("특성")
        case .notifications:
            return AppLocalization.string("알림")
        case .ready:
            return AppLocalization.string("준비")
        case .disconnected:
            return AppLocalization.string(
                "연결 해제"
            )
        case .reconnecting:
            return AppLocalization.string("재연결")
        case .packets:
            return AppLocalization.string("패킷")
        case .timeSync:
            return AppLocalization.string(
                "시간 동기화"
            )
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
            return AppLocalization.string(
                "리모컨 검색 전"
            )
        case .preparing:
            return AppLocalization.string(
                "Bluetooth 준비 중"
            )
        case .scanning:
            return AppLocalization.string(
                "Rivo 리모컨 검색 중"
            )
        case .connecting(let name):
            return AppLocalization.format(
                "%@ 연결 중",
                name
            )
        case .discovering(let name):
            return AppLocalization.format(
                "%@ 서비스 확인 중",
                name
            )
        case .ready(let name):
            return AppLocalization.format(
                "%@ 연결됨",
                name
            )
        case .bluetoothOff:
            return AppLocalization.string(
                "Bluetooth가 꺼져 있습니다"
            )
        case .permissionDenied:
            return AppLocalization.string(
                "Bluetooth 권한이 필요합니다"
            )
        case .unsupported:
            return AppLocalization.string(
                "Bluetooth LE를 지원하지 않습니다"
            )
        case .disconnected:
            return AppLocalization.string(
                "리모컨 연결 끊김"
            )
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
            return AppLocalization.string(
                "연결 후 자동으로 맞춥니다."
            )
        case .sending:
            return AppLocalization.string(
                "현재 시간을 보내는 중"
            )
        case .sent:
            return AppLocalization.string(
                "현재 시간을 전송했습니다."
            )
        case .failed(let message):
            return message
        }
    }
}

nonisolated struct RivoReconnectAttempt:
    Equatable,
    Sendable
{
    let number: Int
    let delay: TimeInterval

    var title: String {
        let seconds = Int(delay.rounded())
        return AppLocalization.format(
            "%lld초 뒤 자동으로 다시 연결합니다. %lld번째 재시도",
            seconds,
            number
        )
    }
}

nonisolated struct RivoReconnectBackoff:
    Equatable,
    Sendable
{
    static let delays: [TimeInterval] = [
        1, 2, 4, 8, 16, 30
    ]

    private(set) var failureCount = 0

    mutating func nextAttempt() -> RivoReconnectAttempt {
        let delay = Self.delays[
            min(failureCount, Self.delays.count - 1)
        ]
        failureCount += 1
        return RivoReconnectAttempt(
            number: failureCount,
            delay: delay
        )
    }

    mutating func reset() {
        failureCount = 0
    }
}

nonisolated enum RivoDeviceSelectionPolicy {
    static func reconnectIdentifier(
        pending: UUID?,
        saved: UUID?
    ) -> UUID? {
        pending ?? saved
    }

    static func shouldAutomaticallyConnect(
        discovered identifier: UUID,
        saved: UUID?,
        requiresManualSelection: Bool
    ) -> Bool {
        !requiresManualSelection
            && identifier == saved
    }
}

nonisolated enum RivoRestoredPeripheralState:
    Int,
    Equatable,
    Hashable,
    Sendable
{
    case connected
    case connecting
    case disconnected
    case disconnecting
}

nonisolated struct RivoRestoredPeripheralCandidate:
    Equatable,
    Sendable
{
    let identifier: UUID
    let state: RivoRestoredPeripheralState
}

nonisolated enum RivoRestorationAction:
    Equatable,
    Sendable
{
    case resumeServices
    case awaitConnection
    case connect
    case awaitDisconnection

    var diagnosticTitle: String {
        switch self {
        case .resumeServices:
            return AppLocalization.string(
                "연결된 서비스 검색을 재개합니다."
            )
        case .awaitConnection:
            return AppLocalization.string(
                "진행 중인 연결을 기다립니다."
            )
        case .connect:
            return AppLocalization.string(
                "복원된 기기에 다시 연결합니다."
            )
        case .awaitDisconnection:
            return AppLocalization.string(
                "연결 해제가 끝난 뒤 다시 연결합니다."
            )
        }
    }
}

nonisolated struct RivoRestorationDecision:
    Equatable,
    Sendable
{
    let candidate:
        RivoRestoredPeripheralCandidate
    let action: RivoRestorationAction
}

nonisolated enum RivoRestorationPolicy {
    static func shouldPrepareCentralManager(
        savedIdentifier: UUID?,
        hasActivatedBluetooth: Bool
    ) -> Bool {
        savedIdentifier != nil
            || hasActivatedBluetooth
    }

    static func decision(
        candidates:
            [RivoRestoredPeripheralCandidate],
        savedIdentifier: UUID?
    ) -> RivoRestorationDecision? {
        guard !candidates.isEmpty else {
            return nil
        }
        let selected =
            savedIdentifier.flatMap {
                saved in
                candidates.first {
                    $0.identifier == saved
                }
            }
            ?? candidates.enumerated()
                .min {
                    lhs,
                    rhs in
                    let leftRank =
                        rank(lhs.element.state)
                    let rightRank =
                        rank(rhs.element.state)
                    if leftRank == rightRank {
                        return lhs.offset
                            < rhs.offset
                    }
                    return leftRank < rightRank
                }?
                .element
        guard let selected else {
            return nil
        }
        return RivoRestorationDecision(
            candidate: selected,
            action: action(
                for: selected.state
            )
        )
    }

    private static func rank(
        _ state: RivoRestoredPeripheralState
    ) -> Int {
        switch state {
        case .connected:
            return 0
        case .connecting:
            return 1
        case .disconnected:
            return 2
        case .disconnecting:
            return 3
        }
    }

    private static func action(
        for state: RivoRestoredPeripheralState
    ) -> RivoRestorationAction {
        switch state {
        case .connected:
            return .resumeServices
        case .connecting:
            return .awaitConnection
        case .disconnected:
            return .connect
        case .disconnecting:
            return .awaitDisconnection
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
            return AppLocalization.string(
                "매우 강함"
            )
        case -70 ..< -55:
            return AppLocalization.string("강함")
        case -85 ..< -70:
            return AppLocalization.string("보통")
        default:
            return AppLocalization.string("약함")
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
        static let hasActivatedBluetooth =
            "rivo.remote.hasActivatedBluetooth"
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
        .inactive {
        didSet {
            RivoWidgetStatusStore.save(
                state: state
            )
        }
    }
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
    @Published private(set) var reconnectAttempt:
        RivoReconnectAttempt?

    private let defaults: UserDefaults
    private var centralManager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveredTypes: [UUID: RivoDeviceType] = [:]
    private var activePeripheral: CBPeripheral?
    private var pendingRestoredPeripheralIdentifier:
        UUID?
    private var restoredOperationIsActive = false
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var assembler = RivoPacketAssembler()
    private var wantsScan = false
    private var shouldReconnect = false
    private var connectionTimeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectBackoff = RivoReconnectBackoff()
    private var pendingPreferredPeripheralIdentifier:
        UUID?
    private var requiresManualDeviceSelection = false
    private var intentionallyDisconnectingIdentifiers =
        Set<UUID>()
    private var periodicTimeSyncTask:
        Task<Void, Never>?
    private var automaticTimeSyncPeripheralIdentifier:
        UUID?
    private var pendingCharacteristicDiscoveryCount = 0
    private var didFinishCharacteristicDiscovery = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        RivoWidgetStatusStore.save(
            state: state
        )
        restoreConnectionDiagnostics()

        if savedPeripheralIdentifier != nil {
            shouldReconnect = true
            recordDiagnostic(
                .info,
                stage: .reconnecting,
                message:
                    AppLocalization.string(
                        "저장된 Rivo 자동 연결을 준비합니다."
                    )
            )
        }
        if RivoRestorationPolicy
            .shouldPrepareCentralManager(
                savedIdentifier:
                    savedPeripheralIdentifier,
                hasActivatedBluetooth:
                    defaults.bool(
                        forKey:
                            DefaultsKey
                            .hasActivatedBluetooth
                    )
            ) {
            prepareCentralManager(
                showPowerAlert: false
            )
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

    var canReturnToSavedDevice: Bool {
        guard let pending =
                pendingPreferredPeripheralIdentifier,
              let saved = savedPeripheralIdentifier else {
            return false
        }
        return pending != saved
    }

    func activateAndScan() {
        guard !state.isReady else {
            return
        }
        guard reconnectTask == nil else {
            return
        }
        switch state {
        case .preparing,
             .scanning,
             .connecting,
             .discovering:
            return
        default:
            break
        }
        resetReconnectBackoff()
        wantsScan = true
        shouldReconnect = true
        prepareCentralManager()
        guard let centralManager,
              centralManager.state == .poweredOn else {
            return
        }
        if reconnectIdentifier != nil {
            attemptSavedConnection()
        } else {
            startScanning()
        }
    }

    func startScanning() {
        pendingPreferredPeripheralIdentifier = nil
        pendingRestoredPeripheralIdentifier = nil
        restoredOperationIsActive = false
        requiresManualDeviceSelection = false
        resetReconnectBackoff()
        beginScanning()
    }

    func searchForAnotherDevice() {
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        resetReconnectBackoff()
        pendingPreferredPeripheralIdentifier = nil
        pendingRestoredPeripheralIdentifier = nil
        restoredOperationIsActive = false
        requiresManualDeviceSelection = true
        wantsScan = true
        shouldReconnect = true
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier = nil
        timeSyncState = .idle
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedDeviceType = nil
        assembler.reset()

        if let activePeripheral {
            intentionallyDisconnectingIdentifiers.insert(
                activePeripheral.identifier
            )
            centralManager?.cancelPeripheralConnection(
                activePeripheral
            )
        }
        recordDiagnostic(
            .info,
            stage: .scanning,
            message:
                AppLocalization.string(
                    "기존 선호 기기는 보존하고 다른 Rivo를 찾습니다."
                )
        )
        beginScanning()
    }

    func retryConnectionNow() {
        guard !state.isReady else {
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        resetReconnectBackoff()
        wantsScan = true
        shouldReconnect = true
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message:
                AppLocalization.string(
                    "사용자가 Rivo 연결을 지금 다시 시도합니다."
                )
        )
        prepareCentralManager()
        guard let centralManager else {
            return
        }
        guard centralManager.state == .poweredOn else {
            updateState(for: centralManager.state)
            return
        }
        if reconnectIdentifier != nil {
            attemptSavedConnection()
        } else {
            beginScanning()
        }
    }

    func reconnectSavedDevice() {
        guard savedPeripheralIdentifier != nil else {
            return
        }
        pendingPreferredPeripheralIdentifier = nil
        requiresManualDeviceSelection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        resetReconnectBackoff()
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message:
                AppLocalization.string(
                    "새 기기 선택을 취소하고 저장된 Rivo로 돌아갑니다."
                )
        )
        retryConnectionNow()
    }

    private func beginScanning() {
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
                AppLocalization.string(
                    "Rivo 서비스 UUID와 기기 이름을 함께 검색합니다."
                )
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
        shouldReconnect = false
        pendingPreferredPeripheralIdentifier = nil
        pendingRestoredPeripheralIdentifier = nil
        restoredOperationIsActive = false
        requiresManualDeviceSelection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = nil
        centralManager?.stopScan()
        if case .scanning = state {
            state = .inactive
            recordDiagnostic(
                .info,
                stage: .scanning,
                message:
                    AppLocalization.string(
                        "사용자가 검색을 중지했습니다."
                    )
            )
        }
    }

    func connect(to device: RivoDiscoveredDevice) {
        guard let peripheral = peripherals[device.id],
              let centralManager else {
            let message =
                AppLocalization.string(
                    "검색 결과가 만료되었습니다. 다시 검색해 주세요."
                )
            state = .failed(message)
            recordDiagnostic(
                .failure,
                stage: .connecting,
                message: message
            )
            return
        }
        resetReconnectBackoff()
        pendingRestoredPeripheralIdentifier = nil
        restoredOperationIsActive = false
        pendingPreferredPeripheralIdentifier = device.id
        requiresManualDeviceSelection = false
        discoveredTypes[device.id] = device.type
        connect(peripheral, using: centralManager)
    }

    func disconnect() {
        wantsScan = false
        shouldReconnect = false
        pendingPreferredPeripheralIdentifier = nil
        pendingRestoredPeripheralIdentifier = nil
        restoredOperationIsActive = false
        requiresManualDeviceSelection = false
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        resetReconnectBackoff()
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier =
            nil
        timeSyncState = .idle
        guard let activePeripheral else {
            state = .disconnected
            recordDiagnostic(
                .info,
                stage: .disconnected,
                message:
                    AppLocalization.string(
                        "연결할 Rivo가 없습니다."
                    )
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
            message:
                AppLocalization.string(
                    "사용자가 Rivo 연결을 끊었습니다."
                )
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
                AppLocalization.string(
                    "Rivo가 연결된 뒤 다시 시도해 주세요."
                )
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
                AppLocalization.string(
                    "이 Rivo의 시간 쓰기 특성을 지원하지 않습니다."
                )
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

    private var reconnectIdentifier: UUID? {
        RivoDeviceSelectionPolicy.reconnectIdentifier(
            pending:
                pendingPreferredPeripheralIdentifier,
            saved: savedPeripheralIdentifier
        )
    }

    private func prepareCentralManager(
        showPowerAlert: Bool = true
    ) {
        guard centralManager == nil else {
            return
        }
        state = .preparing
        defaults.set(
            true,
            forKey:
                DefaultsKey
                .hasActivatedBluetooth
        )
        recordDiagnostic(
            .info,
            stage: .bluetooth,
            message:
                AppLocalization.string(
                    "Bluetooth 중앙 장치를 준비합니다."
                )
        )
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey:
                    Self.restorationIdentifier,
                CBCentralManagerOptionShowPowerAlertKey:
                    showPowerAlert
            ]
        )
    }

    private func attemptSavedConnection() {
        guard let centralManager,
              centralManager.state == .poweredOn,
              let identifier = reconnectIdentifier else {
            beginScanning()
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
                    AppLocalization.string(
                        "저장된 Rivo를 찾지 못해 주변 검색으로 전환합니다."
                    )
            )
            beginScanning()
            return
        }
        if identifier == savedPeripheralIdentifier,
           let savedDeviceType {
            discoveredTypes[identifier] =
                savedDeviceType
        }
        peripherals[identifier] = peripheral
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message:
                pendingPreferredPeripheralIdentifier
                    == identifier
                ? AppLocalization.string(
                    "선택한 Rivo에 다시 연결합니다."
                )
                : AppLocalization.string(
                    "저장된 Rivo에 다시 연결합니다."
                )
        )
        connect(peripheral, using: centralManager)
    }

    private func connect(
        _ peripheral: CBPeripheral,
        using centralManager: CBCentralManager
    ) {
        pendingRestoredPeripheralIdentifier =
            nil
        centralManager.stopScan()
        wantsScan = false
        connectionTimeoutTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = nil

        if let activePeripheral,
           activePeripheral.identifier != peripheral.identifier {
            intentionallyDisconnectingIdentifiers.insert(
                activePeripheral.identifier
            )
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
                AppLocalization.format(
                    "%@ 연결을 시작합니다.",
                    displayName(for: peripheral)
                )
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
                AppLocalization.string(
                    "Rivo 연결 또는 준비 시간이 10초를 초과했습니다."
                )
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
        guard shouldReconnect,
              reconnectTask == nil else {
            return
        }
        let attempt = reconnectBackoff.nextAttempt()
        reconnectAttempt = attempt
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message: attempt.title
        )
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds:
                    UInt64(
                        attempt.delay
                            * 1_000_000_000
                    )
            )
            guard !Task.isCancelled,
                  let self,
                  self.shouldReconnect else {
                return
            }
            self.reconnectTask = nil
            self.reconnectAttempt = nil
            if self.reconnectIdentifier != nil {
                self.attemptSavedConnection()
            } else {
                self.beginScanning()
            }
        }
    }

    private func resetReconnectBackoff() {
        reconnectBackoff.reset()
        reconnectAttempt = nil
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
        return AppLocalization.string(
            "Rivo 리모컨"
        )
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

    private func restoredState(
        for state: CBPeripheralState
    ) -> RivoRestoredPeripheralState {
        switch state {
        case .connected:
            return .connected
        case .connecting:
            return .connecting
        case .disconnected:
            return .disconnected
        case .disconnecting:
            return .disconnecting
        @unknown default:
            return .disconnected
        }
    }

    @discardableResult
    private func resumePendingRestoredPeripheral(
        using central: CBCentralManager
    ) -> Bool {
        guard let identifier =
                pendingRestoredPeripheralIdentifier,
              let peripheral =
                peripherals[identifier] else {
            pendingRestoredPeripheralIdentifier =
                nil
            return false
        }
        pendingRestoredPeripheralIdentifier =
            nil
        shouldReconnect = true
        wantsScan = false
        activePeripheral = peripheral
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

        switch peripheral.state {
        case .connected:
            resetReconnectBackoff()
            connectionTimeoutTask?.cancel()
            state = .discovering(
                displayName(for: peripheral)
            )
            recordDiagnostic(
                .info,
                stage: .services,
                message:
                    AppLocalization.string(
                        "복원된 Rivo의 GATT 서비스를 다시 확인합니다."
                    )
            )
            peripheral.discoverServices(nil)
        case .connecting:
            state = .connecting(
                displayName(for: peripheral)
            )
            recordDiagnostic(
                .info,
                stage: .connecting,
                message:
                    AppLocalization.string(
                        "iPadOS가 진행 중이던 Rivo 연결을 기다립니다."
                    )
            )
            scheduleConnectionTimeout(
                for: peripheral.identifier
            )
        case .disconnected:
            recordDiagnostic(
                .info,
                stage: .reconnecting,
                message:
                    AppLocalization.string(
                        "복원된 Rivo가 끊겨 있어 다시 연결합니다."
                    )
            )
            connect(
                peripheral,
                using: central
            )
        case .disconnecting:
            state = .disconnected
            recordDiagnostic(
                .info,
                stage: .reconnecting,
                message:
                    AppLocalization.string(
                        "복원된 Rivo의 연결 해제가 끝나기를 기다립니다."
                    )
            )
        @unknown default:
            state = .disconnected
            scheduleReconnect()
        }
        return true
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
        reconnectTask?.cancel()
        reconnectTask = nil
        resetReconnectBackoff()
        connectedDeviceType = type
        defaults.set(
            peripheral.identifier.uuidString,
            forKey: DefaultsKey.peripheralIdentifier
        )
        defaults.set(
            type.rawValue,
            forKey: DefaultsKey.deviceType
        )
        pendingPreferredPeripheralIdentifier = nil
        requiresManualDeviceSelection = false
        restoredOperationIsActive = false
        state = .ready(displayName(for: peripheral))
        recordDiagnostic(
            .success,
            stage: .ready,
            message:
                AppLocalization.format(
                    "%@ 버튼 수신 준비가 끝났습니다.",
                    displayName(for: peripheral)
                )
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
            message:
                AppLocalization.string(
                    "Rivo에 iPad 현재 시간을 전송했습니다."
                )
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
            missing.append(
                AppLocalization.string(
                    "UART 쓰기"
                )
            )
        }
        if notifyCharacteristic == nil {
            missing.append(
                AppLocalization.string(
                    "UART 알림"
                )
            )
        }
        guard missing.isEmpty else {
            let message =
                AppLocalization.format(
                    "필수 %@ 특성을 찾지 못했습니다.",
                    missing.joined(separator: "·")
                )
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
            message:
                AppLocalization.string(
                    "UART 쓰기·알림 특성을 확인했습니다."
                )
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
                message:
                    AppLocalization.string(
                        "Bluetooth를 사용할 수 있습니다."
                    )
            )
            if let centralManager,
               resumePendingRestoredPeripheral(
                   using: centralManager
               ) {
                return
            }
            if restoredOperationIsActive {
                if let activePeripheral {
                    switch activePeripheral.state {
                    case .connected,
                         .connecting,
                         .disconnecting:
                        return
                    case .disconnected:
                        break
                    @unknown default:
                        break
                    }
                }
                if wantsScan,
                   centralManager?.isScanning == true {
                    state = .scanning
                    return
                }
                restoredOperationIsActive = false
            }
            if shouldReconnect,
               reconnectIdentifier != nil {
                attemptSavedConnection()
            } else if wantsScan {
                startScanning()
            } else {
                state = .inactive
            }
        case .poweredOff:
            connectionTimeoutTask?.cancel()
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = nil
            state = .bluetoothOff
            recordDiagnostic(
                .warning,
                stage: .bluetooth,
                message:
                    AppLocalization.string(
                        "Bluetooth가 꺼져 있습니다."
                    )
            )
        case .unauthorized:
            connectionTimeoutTask?.cancel()
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = nil
            state = .permissionDenied
            recordDiagnostic(
                .failure,
                stage: .bluetooth,
                message:
                    AppLocalization.string(
                        "Bluetooth 권한이 허용되지 않았습니다."
                    )
            )
        case .unsupported:
            connectionTimeoutTask?.cancel()
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = nil
            state = .unsupported
            recordDiagnostic(
                .failure,
                stage: .bluetooth,
                message:
                    AppLocalization.string(
                        "이 기기는 Bluetooth LE를 지원하지 않습니다."
                    )
            )
        case .resetting:
            connectionTimeoutTask?.cancel()
            state = .preparing
            recordDiagnostic(
                .warning,
                stage: .bluetooth,
                message:
                    AppLocalization.string(
                        "Bluetooth가 재설정되고 있습니다."
                    )
            )
        case .unknown:
            state = .preparing
            recordDiagnostic(
                .info,
                stage: .bluetooth,
                message:
                    AppLocalization.string(
                        "Bluetooth 상태를 확인하고 있습니다."
                    )
            )
        @unknown default:
            let message =
                AppLocalization.string(
                    "알 수 없는 Bluetooth 상태입니다."
                )
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
        let restored = dict[
            CBCentralManagerRestoredStatePeripheralsKey
        ] as? [CBPeripheral] ?? []
        let candidates = restored.map {
            RivoRestoredPeripheralCandidate(
                identifier: $0.identifier,
                state:
                    restoredState(
                        for: $0.state
                    )
            )
        }
        guard let decision =
                RivoRestorationPolicy
                .decision(
                    candidates: candidates,
                    savedIdentifier:
                        savedPeripheralIdentifier
                ),
              let peripheral =
                restored.first(
                    where: {
                        $0.identifier
                            == decision
                            .candidate
                            .identifier
                    }
                ) else {
            let restoredScan =
                central.isScanning
                || dict[
                    CBCentralManagerRestoredStateScanServicesKey
                ] != nil
                || dict[
                    CBCentralManagerRestoredStateScanOptionsKey
                ] != nil
            guard restoredScan else {
                return
            }
            wantsScan = true
            shouldReconnect = true
            restoredOperationIsActive = true
            state = .scanning
            recordDiagnostic(
                .info,
                stage: .reconnecting,
                message:
                    AppLocalization.string(
                        "iPadOS가 복원한 Rivo 검색을 이어받았습니다."
                    )
            )
            return
        }
        shouldReconnect = true
        wantsScan = false
        restoredOperationIsActive = true
        for item in restored {
            peripherals[item.identifier] = item
        }
        activePeripheral = peripheral
        peripheral.delegate = self
        if peripheral.identifier
                == savedPeripheralIdentifier,
           let savedDeviceType {
            discoveredTypes[
                peripheral.identifier
            ] = savedDeviceType
        }
        pendingRestoredPeripheralIdentifier =
            peripheral.identifier
        recordDiagnostic(
            .info,
            stage: .reconnecting,
            message:
                AppLocalization.format(
                    "iPadOS가 복원한 Rivo 연결을 이어받았습니다. %@",
                    decision.action.diagnosticTitle
                )
        )

        if central.state == .poweredOn {
            _ = resumePendingRestoredPeripheral(
                using: central
            )
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
                    AppLocalization.format(
                        "%@을 %@으로 찾았습니다.",
                        name,
                        match.source.title
                    )
            )
        }
        discoveredDevices.sort {
            $0.signalStrength > $1.signalStrength
        }

        if RivoDeviceSelectionPolicy
            .shouldAutomaticallyConnect(
                discovered:
                    peripheral.identifier,
                saved: savedPeripheralIdentifier,
                requiresManualSelection:
                    requiresManualDeviceSelection
            ) {
            connect(peripheral, using: central)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        pendingRestoredPeripheralIdentifier =
            nil
        restoredOperationIsActive = false
        activePeripheral = peripheral
        peripheral.delegate = self
        state = .discovering(displayName(for: peripheral))
        recordDiagnostic(
            .success,
            stage: .connecting,
            message:
                AppLocalization.format(
                    "%@ BLE 연결에 성공했습니다.",
                    displayName(for: peripheral)
                )
        )
        recordDiagnostic(
            .info,
            stage: .services,
            message:
                AppLocalization.string(
                    "GATT 서비스를 확인합니다."
                )
        )
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        restoredOperationIsActive = false
        connectionTimeoutTask?.cancel()
        let message = connectionErrorMessage(
            error,
            fallback:
                AppLocalization.string(
                    "Rivo 리모컨에 연결하지 못했습니다."
                )
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
        restoredOperationIsActive = false
        if intentionallyDisconnectingIdentifiers
            .remove(peripheral.identifier) != nil {
            if activePeripheral?.identifier
                == peripheral.identifier {
                activePeripheral = nil
            }
            recordDiagnostic(
                .info,
                stage: .disconnected,
                message:
                    AppLocalization.format(
                        "%@ 연결을 기기 전환을 위해 종료했습니다.",
                        displayName(for: peripheral)
                    )
            )
            if central.isScanning {
                state = .scanning
            }
            return
        }
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
                    AppLocalization.format(
                        "%@ 연결이 끊겼습니다.",
                        displayName(for: peripheral)
                    )
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
                fallback:
                    AppLocalization.string(
                        "GATT 서비스 검색에 실패했습니다."
                    )
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
                AppLocalization.string(
                    "Rivo에서 GATT 서비스를 찾지 못했습니다."
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
        if let type = deviceType(
            from: services.map(\.uuid)
        ) {
            discoveredTypes[peripheral.identifier] = type
        }
        recordDiagnostic(
            .success,
            stage: .services,
            message:
                AppLocalization.format(
                    "GATT 서비스 %lld개를 찾았습니다.",
                    services.count
                )
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
                        AppLocalization.format(
                            "%@ 특성 검색에 실패했습니다.",
                            service.uuid.uuidString
                        )
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
                fallback:
                    AppLocalization.string(
                        "UART 알림 구독에 실패했습니다."
                    )
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
                AppLocalization.string(
                    "Rivo가 UART 알림 구독을 활성화하지 않았습니다."
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
        recordDiagnostic(
            .success,
            stage: .notifications,
            message:
                AppLocalization.string(
                    "UART 버튼 알림 구독을 시작했습니다."
                )
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
                            AppLocalization.string(
                                "Rivo 버튼 알림을 읽지 못했습니다."
                            )
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
                            AppLocalization.format(
                                "해석하지 못한 Rivo 패킷이 %lld개입니다.",
                                invalidPacketCount
                            )
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
                AppLocalization.format(
                    "현재 시간을 보내지 못했습니다: %@",
                    error.localizedDescription
                )
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
