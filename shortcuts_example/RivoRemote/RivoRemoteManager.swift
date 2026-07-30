@preconcurrency import CoreBluetooth
import Combine
import Foundation

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
    }

    private static let threeService = CBUUID(string: "F120")
    private static let miniService = CBUUID(string: "F121")
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
    @Published private(set) var eventSequence = 0
    @Published private(set) var invalidPacketCount = 0
    @Published private(set) var connectedDeviceType:
        RivoDeviceType?
    @Published private(set) var timeSyncState:
        RivoTimeSyncState = .idle

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()

        if savedPeripheralIdentifier != nil {
            shouldReconnect = true
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
        centralManager.scanForPeripherals(
            withServices: [
                Self.threeService,
                Self.miniService
            ],
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
        }
    }

    func connect(to device: RivoDiscoveredDevice) {
        guard let peripheral = peripherals[device.id],
              let centralManager else {
            state = .failed(
                "검색 결과가 만료되었습니다. 다시 검색해 주세요."
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
            return
        }
        centralManager?.cancelPeripheralConnection(
            activePeripheral
        )
        state = .disconnected
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
        state = .inactive
    }

    func clearEventHistory() {
        recentEvents = []
        invalidPacketCount = 0
    }

    func syncTime() {
        guard state.isReady,
              let peripheral = activePeripheral,
              let characteristic =
                writeCharacteristic else {
            timeSyncState = .failed(
                "Rivo가 연결된 뒤 다시 시도해 주세요."
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
            timeSyncState = .failed(
                "이 Rivo의 시간 쓰기 특성을 지원하지 않습니다."
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
            startScanning()
            return
        }
        if let savedDeviceType {
            discoveredTypes[identifier] = savedDeviceType
        }
        peripherals[identifier] = peripheral
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
        periodicTimeSyncTask?.cancel()
        automaticTimeSyncPeripheralIdentifier =
            nil
        timeSyncState = .idle
        assembler.reset()
        state = .connecting(displayName(for: peripheral))
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
            self.state = .failed(
                "Rivo 연결 시간이 초과되었습니다."
            )
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else {
            return
        }
        reconnectTask?.cancel()
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
        guard let peripheral = activePeripheral,
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
        if automaticTimeSyncPeripheralIdentifier
            != peripheral.identifier {
            automaticTimeSyncPeripheralIdentifier =
                peripheral.identifier
            syncTime()
        }
    }

    private func noteTimePacketSent() {
        timeSyncState = .sent(Date())
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

    private func updateState(
        for managerState: CBManagerState
    ) {
        switch managerState {
        case .poweredOn:
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
        case .unauthorized:
            state = .permissionDenied
        case .unsupported:
            state = .unsupported
        case .resetting:
            state = .preparing
        case .unknown:
            state = .preparing
        @unknown default:
            state = .failed(
                "알 수 없는 Bluetooth 상태입니다."
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
        guard let type = deviceType(
            from: advertisedServices
        ) else {
            return
        }
        let advertisedName = advertisementData[
            CBAdvertisementDataLocalNameKey
        ] as? String
        let name = advertisedName
            ?? peripheral.name
            ?? type.title
        let device = RivoDiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            type: type,
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
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionTimeoutTask?.cancel()
        state = .failed(
            error?.localizedDescription
                ?? "Rivo 리모컨에 연결하지 못했습니다."
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
        if !shouldReconnect,
           savedPeripheralIdentifier == nil {
            state = .inactive
        } else {
            state = error.map {
                .failed($0.localizedDescription)
            } ?? .disconnected
        }
        scheduleReconnect()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            state = .failed(error.localizedDescription)
            centralManager?.cancelPeripheralConnection(
                peripheral
            )
            return
        }
        let services = peripheral.services ?? []
        if let type = deviceType(
            from: services.map(\.uuid)
        ) {
            discoveredTypes[peripheral.identifier] = type
        }
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
        if let error {
            state = .failed(error.localizedDescription)
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
        markReadyIfPossible()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic:
            CBCharacteristic,
        error: Error?
    ) {
        if let error {
            state = .failed(error.localizedDescription)
            return
        }
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
            }
            return
        }

        for packet in assembler.append(value) {
            guard let input = RivoRemotePacketParser.parse(
                packet
            ) else {
                invalidPacketCount += 1
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
            if recentEvents.count > 30 {
                recentEvents.removeLast(
                    recentEvents.count - 30
                )
            }
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
            timeSyncState = .failed(
                "현재 시간을 보내지 못했습니다: "
                    + error.localizedDescription
            )
        } else {
            noteTimePacketSent()
        }
    }
}
