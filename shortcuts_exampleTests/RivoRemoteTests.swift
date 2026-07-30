import CoreImage
import Foundation
import XCTest

@testable import shortcuts_example

final class RivoRemoteProtocolTests: XCTestCase {
    func testReconnectBackoffGrowsAndCapsUntilReset() {
        var backoff = RivoReconnectBackoff()
        let attempts = (0 ..< 8).map { _ in
            backoff.nextAttempt()
        }

        XCTAssertEqual(
            attempts.map(\.delay),
            [1, 2, 4, 8, 16, 30, 30, 30]
        )
        XCTAssertEqual(
            attempts.map(\.number),
            Array(1 ... 8)
        )
        XCTAssertEqual(
            attempts[2].title,
            "4초 뒤 자동으로 다시 연결합니다. 3번째 재시도"
        )

        backoff.reset()

        XCTAssertEqual(
            backoff.nextAttempt(),
            RivoReconnectAttempt(
                number: 1,
                delay: 1
            )
        )
    }

    func testDeviceSelectionKeepsSavedFallbackButHonorsManualScan() {
        let saved = UUID()
        let pending = UUID()

        XCTAssertEqual(
            RivoDeviceSelectionPolicy
                .reconnectIdentifier(
                    pending: pending,
                    saved: saved
                ),
            pending
        )
        XCTAssertEqual(
            RivoDeviceSelectionPolicy
                .reconnectIdentifier(
                    pending: nil,
                    saved: saved
                ),
            saved
        )
        XCTAssertTrue(
            RivoDeviceSelectionPolicy
                .shouldAutomaticallyConnect(
                    discovered: saved,
                    saved: saved,
                    requiresManualSelection: false
                )
        )
        XCTAssertFalse(
            RivoDeviceSelectionPolicy
                .shouldAutomaticallyConnect(
                    discovered: saved,
                    saved: saved,
                    requiresManualSelection: true
                )
        )
        XCTAssertFalse(
            RivoDeviceSelectionPolicy
                .shouldAutomaticallyConnect(
                    discovered: pending,
                    saved: saved,
                    requiresManualSelection: false
                )
        )
    }

    func testTimePacketMatchesAndroidSignedChecksumRange() {
        let packet = RivoTimeSyncPacketEncoder.packet(
            for: RivoClockValue(
                year: 2026,
                month: 7,
                day: 29,
                hour: 18,
                minute: 30,
                second: 45,
                millisecond: 513
            )
        )

        XCTAssertEqual(
            packet,
            Data([
                0x41, 0x54, 0x44, 0x54,
                0x0B, 0x00, 0x01, 0x00,
                0xEA, 0x07, 0x07, 0x1D,
                0x12, 0x1E, 0x2D, 0x01,
                0x02, 0xAC, 0x01, 0x0D,
                0x0A
            ])
        )
    }

    func testTimePacketUsesProvidedCalendarFields() {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone =
            TimeZone(secondsFromGMT: 9 * 60 * 60)!
        let date = calendar.date(
            from: DateComponents(
                year: 2025,
                month: 12,
                day: 31,
                hour: 23,
                minute: 59,
                second: 58
            )
        )!

        let packet = Array(
            RivoTimeSyncPacketEncoder.packet(
                for: date,
                calendar: calendar
            )
        )

        XCTAssertEqual(
            Array(packet[8 ... 16]),
            [
                0xE9, 0x07,
                0x0C, 0x1F, 0x17,
                0x3B, 0x3A,
                0x00, 0x00
            ]
        )
    }

    func testAssemblerReconstructsFragmentedAndCoalescedPackets() {
        let first = makeButtonPacket(key: ascii("-"))
        let second = makeButtonPacket(key: ascii("_"))
        var assembler = RivoPacketAssembler()

        XCTAssertTrue(
            assembler.append(
                first.prefix(3)
            ).isEmpty
        )
        var completed = assembler.append(
            first.dropFirst(3) + second
        )

        XCTAssertEqual(completed, [first, second])
        XCTAssertEqual(
            RivoRemotePacketParser.parse(completed.removeFirst()),
            .button(
                button: .l1,
                action: .pressed,
                rawKey: ascii("-")
            )
        )
        XCTAssertEqual(
            RivoRemotePacketParser.parse(completed.removeFirst()),
            .button(
                button: .l1,
                action: .released,
                rawKey: ascii("_")
            )
        )
    }

    func testAssemblerDropsNoiseAndKeepsSplitStartMarker() {
        let packet = makeButtonPacket(key: ascii("5"))
        var assembler = RivoPacketAssembler()

        XCTAssertTrue(
            assembler.append(
                Data([0x00, 0xFF, ascii("a")])
            ).isEmpty
        )
        let completed = assembler.append(
            packet.dropFirst()
        )

        XCTAssertEqual(completed, [packet])
    }

    func testAssemblerSkipsFalseStartWithInvalidSignature() {
        let packet = makeButtonPacket(key: ascii("6"))
        var bytes = Data([
            ascii("a"), ascii("t"),
            ascii("N"), ascii("O"),
            0xFF, 0xFF
        ])
        bytes.append(packet)
        var assembler = RivoPacketAssembler()

        XCTAssertEqual(
            assembler.append(bytes),
            [packet]
        )
    }

    func testParserMatchesEveryAndroidPressAndReleaseKey() {
        let pairs: [(UInt8, UInt8, RivoButton)] = [
            (ascii("-"), ascii("_"), .l1),
            (ascii("["), ascii("{"), .l2),
            (ascii(";"), ascii(":"), .l3),
            (ascii(","), ascii("<"), .l4),
            (ascii("="), ascii("+"), .r1),
            (ascii("]"), ascii("}"), .r2),
            (ascii("'"), ascii("\""), .r3),
            (ascii("\\"), ascii("|"), .r4),
            (ascii("1"), ascii("!"), .one),
            (ascii("2"), ascii("@"), .two),
            (ascii("3"), ascii("#"), .three),
            (ascii("4"), ascii("$"), .four),
            (ascii("5"), ascii("%"), .five),
            (ascii("6"), ascii("^"), .six),
            (ascii("7"), ascii("&"), .seven),
            (ascii("8"), ascii("*"), .eight),
            (ascii("9"), ascii("("), .nine),
            (ascii("0"), ascii(")"), .zero),
            (ascii("."), ascii(">"), .star),
            (ascii("/"), ascii("?"), .sharp)
        ]

        for (press, release, button) in pairs {
            XCTAssertEqual(
                RivoRemotePacketParser.parse(
                    makeButtonPacket(key: press)
                ),
                .button(
                    button: button,
                    action: .pressed,
                    rawKey: press
                )
            )
            XCTAssertEqual(
                RivoRemotePacketParser.parse(
                    makeButtonPacket(key: release)
                ),
                .button(
                    button: button,
                    action: .released,
                    rawKey: release
                )
            )
        }
    }

    func testParserRecognizesVoiceSequence() {
        let packet = makeSequencePacket("a/")
        var assembler = RivoPacketAssembler()

        let completed = assembler.append(packet)

        XCTAssertEqual(completed, [packet])
        XCTAssertEqual(
            RivoRemotePacketParser.parse(packet),
            .sequence("a/")
        )
    }

    func testParserAcceptsDataWithShiftedStartIndex() {
        let packet = makeButtonPacket(key: ascii("5"))
        var shiftedPacket = Data([0xFF])
        shiftedPacket.append(packet)
        shiftedPacket.removeFirst()

        XCTAssertEqual(
            RivoRemotePacketParser.parse(shiftedPacket),
            .button(
                button: .five,
                action: .pressed,
                rawKey: ascii("5")
            )
        )
    }

    func testDeviceTypeMatchesShortAndBluetoothBaseUUIDs() {
        XCTAssertEqual(
            RivoDeviceType.from(serviceUUID: "F120"),
            .three
        )
        XCTAssertEqual(
            RivoDeviceType.from(
                serviceUUID:
                    "0000F121-0000-1000-8000-00805F9B34FB"
            ),
            .mini
        )
        XCTAssertNil(
            RivoDeviceType.from(serviceUUID: "180F")
        )
    }

    func testAdvertisementClassifierFallsBackToKnownRivoNames() {
        XCTAssertEqual(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [],
                advertisedName: "Rivo Mini 2048",
                peripheralName: nil
            ),
            RivoAdvertisementMatch(
                type: .mini,
                source: .advertisedName
            )
        )
        XCTAssertEqual(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [],
                advertisedName: nil,
                peripheralName: "RIVO-3-A12"
            ),
            RivoAdvertisementMatch(
                type: .three,
                source: .peripheralName
            )
        )
        XCTAssertEqual(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [],
                advertisedName: "RivoThree",
                peripheralName: nil
            )?.type,
            .three
        )
    }

    func testAdvertisementServiceUUIDWinsOverConflictingName() {
        XCTAssertEqual(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [
                    "0000F121-0000-1000-8000-00805F9B34FB"
                ],
                advertisedName: "Rivo 3",
                peripheralName: nil
            ),
            RivoAdvertisementMatch(
                type: .mini,
                source: .serviceUUID
            )
        )
    }

    func testAdvertisementClassifierRejectsGenericNames() {
        XCTAssertNil(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: ["180F"],
                advertisedName: "Rivo",
                peripheralName: "Headphones"
            )
        )
        XCTAssertNil(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [],
                advertisedName: "Arrival Mini",
                peripheralName: nil
            )
        )
        XCTAssertEqual(
            RivoAdvertisementClassifier.match(
                serviceUUIDs: [],
                advertisedName: "Rivo",
                peripheralName: nil,
                savedType: .three
            ),
            RivoAdvertisementMatch(
                type: .three,
                source: .savedDevice
            )
        )
    }

    func testConnectionDiagnosticCodableRoundTrip() throws {
        let diagnostic = RivoConnectionDiagnostic(
            id: UUID(),
            recordedAt: Date(timeIntervalSince1970: 123),
            level: .failure,
            stage: .characteristics,
            message: "UART 알림 특성을 찾지 못했습니다."
        )

        let data = try JSONEncoder().encode([diagnostic])
        let decoded = try JSONDecoder().decode(
            [RivoConnectionDiagnostic].self,
            from: data
        )

        XCTAssertEqual(decoded, [diagnostic])
    }

    private func makeButtonPacket(key: UInt8) -> Data {
        Data([
            ascii("a"), ascii("t"),
            ascii("B"), ascii("T"),
            0, 0,
            0, key,
            13, 10
        ])
    }

    private func makeSequencePacket(
        _ payload: String
    ) -> Data {
        let payloadBytes = Array(payload.utf8)
        var packet = Data([
            ascii("a"), ascii("t"),
            ascii("B"), ascii("T"),
            UInt8(payloadBytes.count), 0,
            2, UInt8(payloadBytes.count)
        ])
        packet.append(contentsOf: payloadBytes)
        packet.append(contentsOf: [13, 10])
        return packet
    }

    private func ascii(_ character: Character) -> UInt8 {
        character.asciiValue!
    }
}

final class RivoButtonGestureRecognizerTests:
    XCTestCase
{
    func testOrdinaryTapMatchesAndroidPressAndReleaseDelays() {
        var recognizer =
            RivoButtonGestureRecognizer()

        XCTAssertTrue(
            recognizer.receive(
                button(.five, action: .pressed),
                at: 10
            ).isEmpty
        )
        XCTAssertTrue(
            recognizer.advance(to: 10.009)
                .isEmpty
        )
        XCTAssertEqual(
            recognizer.advance(to: 10.010),
            [button(.five, action: .pressed)]
        )
        XCTAssertTrue(
            recognizer.receive(
                button(.five, action: .released),
                at: 10.100
            ).isEmpty
        )
        XCTAssertEqual(
            recognizer.advance(to: 10.150),
            [button(.five, action: .released)]
        )
    }

    func testLongPressIncludesPressAndUsesDedicatedEndEvent() {
        var recognizer =
            RivoButtonGestureRecognizer()

        _ = recognizer.receive(
            button(.five, action: .pressed),
            at: 20
        )

        XCTAssertEqual(
            recognizer.advance(to: 20.500),
            [
                button(.five, action: .pressed),
                button(.five, action: .longPressed)
            ]
        )
        XCTAssertEqual(
            recognizer.receive(
                button(.five, action: .released),
                at: 20.750
            ),
            [
                button(
                    .five,
                    action: .longPressEnded
                )
            ]
        )
        XCTAssertNil(recognizer.nextDeadline)
    }

    func testDoubleTapSuppressesModeButtonSingleTap() {
        var recognizer =
            RivoButtonGestureRecognizer()

        XCTAssertTrue(
            recognizer.receive(
                button(.l1, action: .pressed),
                at: 30
            ).isEmpty
        )
        XCTAssertTrue(
            recognizer.receive(
                button(.l1, action: .released),
                at: 30.100
            ).isEmpty
        )
        XCTAssertEqual(
            recognizer.receive(
                button(.l1, action: .pressed),
                at: 30.250
            ),
            [button(.l1, action: .doubleTapped)]
        )
        XCTAssertEqual(
            recognizer.receive(
                button(.l1, action: .released),
                at: 30.300
            ),
            [button(.l1, action: .doubleTapEnded)]
        )
        XCTAssertNil(recognizer.nextDeadline)
    }

    func testModeButtonSingleTapIsConfirmedAfterInterval() {
        var recognizer =
            RivoButtonGestureRecognizer()

        _ = recognizer.receive(
            button(.l1, action: .pressed),
            at: 40
        )
        _ = recognizer.receive(
            button(.l1, action: .released),
            at: 40.100
        )

        XCTAssertTrue(
            recognizer.advance(to: 40.399)
                .isEmpty
        )
        XCTAssertEqual(
            recognizer.advance(to: 40.400),
            [
                button(.l1, action: .pressed),
                button(.l1, action: .released)
            ]
        )
    }

    func testMissingReleaseAutoEndsHoldAfterThreeSeconds() {
        var recognizer =
            RivoButtonGestureRecognizer()

        _ = recognizer.receive(
            button(.eight, action: .pressed),
            at: 50
        )

        XCTAssertEqual(
            recognizer.advance(to: 53),
            [
                button(.eight, action: .pressed),
                button(.eight, action: .longPressed),
                button(
                    .eight,
                    action: .longPressEnded
                )
            ]
        )
        XCTAssertNil(recognizer.nextDeadline)
    }

    func testSequenceBypassesButtonTiming() {
        var recognizer =
            RivoButtonGestureRecognizer()

        XCTAssertEqual(
            recognizer.receive(
                .sequence("a/"),
                at: 60
            ),
            [.sequence("a/")]
        )
    }

    private func button(
        _ button: RivoButton,
        action: RivoButtonAction
    ) -> RivoRemoteInput {
        .button(
            button: button,
            action: action,
            rawKey: 0
        )
    }
}

@MainActor
final class RivoRemoteControlCenterTests: XCTestCase {
    func testRemoteManagerRestoresAndClearsDiagnostics() throws {
        let suiteName =
            "RivoRemoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let diagnostic = RivoConnectionDiagnostic(
            id: UUID(),
            recordedAt: Date(timeIntervalSince1970: 456),
            level: .warning,
            stage: .services,
            message: "서비스 확인 기록"
        )
        defaults.set(
            try JSONEncoder().encode([diagnostic]),
            forKey: "rivo.remote.connectionDiagnostics"
        )

        let manager =
            RivoRemoteManager(defaults: defaults)

        XCTAssertEqual(
            manager.connectionDiagnostics,
            [diagnostic]
        )
        manager.clearConnectionDiagnostics()
        XCTAssertTrue(
            manager.connectionDiagnostics.isEmpty
        )
        XCTAssertNil(
            defaults.data(
                forKey:
                    "rivo.remote.connectionDiagnostics"
            )
        )
    }

    func testQuickMenuNavigationSelectsReader() {
        let controlCenter = RivoRemoteControlCenter()

        XCTAssertNil(
            controlCenter.receive(
                button(.l1, action: .pressed)
            )
        )
        XCTAssertTrue(controlCenter.isMenuPresented)

        XCTAssertNil(
            controlCenter.receive(
                button(.six, action: .pressed)
            )
        )
        XCTAssertEqual(controlCenter.selectedIndex, 1)

        XCTAssertEqual(
            controlCenter.receive(
                button(.five, action: .pressed)
            ),
            .navigate(.reader)
        )
        XCTAssertFalse(controlCenter.isMenuPresented)
    }

    func testReleaseDoesNotTriggerMenuAndGlobalCommandsWork() {
        let controlCenter = RivoRemoteControlCenter()

        XCTAssertNil(
            controlCenter.receive(
                button(.l1, action: .released)
            )
        )
        XCTAssertFalse(controlCenter.isMenuPresented)
        XCTAssertEqual(
            controlCenter.receive(
                button(.r3, action: .pressed)
            ),
            .stopSpeech
        )
        XCTAssertEqual(
            controlCenter.receive(.sequence("a/")),
            .startVoiceAction
        )
    }

    func testL1DoubleTapAlwaysPresentsQuickMenuGuide() {
        let controlCenter = RivoRemoteControlCenter()

        XCTAssertNil(
            controlCenter.receive(
                button(.l1, action: .doubleTapped)
            )
        )
        XCTAssertTrue(controlCenter.isMenuPresented)

        XCTAssertNil(
            controlCenter.receive(
                button(.l1, action: .doubleTapped)
            )
        )
        XCTAssertTrue(controlCenter.isMenuPresented)
    }

    func testClosedMenuLeavesScreenButtonsForActiveFeature() {
        let controlCenter = RivoRemoteControlCenter()

        let screenDecision =
            controlCenter.receiveDecision(
                button(.seven, action: .pressed)
            )

        XCTAssertFalse(screenDecision.consumed)
        XCTAssertNil(screenDecision.command)

        _ = controlCenter.receiveDecision(
            button(.l1, action: .pressed)
        )
        let menuDecision =
            controlCenter.receiveDecision(
                button(.five, action: .pressed)
            )

        XCTAssertTrue(menuDecision.consumed)
        XCTAssertEqual(
            menuDecision.command,
            .navigate(.aiChat)
        )
    }

    func testUnavailableScreenViewModesExplainIPadLimit() {
        let controlCenter = RivoRemoteControlCenter()

        let jumpDecision =
            controlCenter.receiveDecision(
                button(.l4, action: .pressed)
            )

        XCTAssertTrue(jumpDecision.consumed)
        XCTAssertNil(jumpDecision.command)
        XCTAssertTrue(
            controlCenter.feedback.contains(
                "iPadOS"
            )
        )

        let scrollGuide =
            controlCenter.receiveDecision(
                button(.r4, action: .doubleTapped)
            )

        XCTAssertTrue(scrollGuide.consumed)
        XCTAssertNil(scrollGuide.command)
        XCTAssertTrue(
            controlCenter.feedback.contains(
                "화면 연속 이동 안내"
            )
        )
    }

    func testModeGuidesExplainWhereLocalActionsWork() {
        let controlCenter = RivoRemoteControlCenter()

        XCTAssertTrue(
            controlCenter.receiveDecision(
                button(.r1, action: .doubleTapped)
            ).consumed
        )
        XCTAssertTrue(
            controlCenter.feedback.contains(
                "카메라 돋보기"
            )
        )

        XCTAssertTrue(
            controlCenter.receiveDecision(
                button(.l3, action: .doubleTapped)
            ).consumed
        )
        XCTAssertTrue(
            controlCenter.feedback.contains(
                "TXT 또는 PDF"
            )
        )
    }

    func testScreenMapperMatchesAndroidCameraAndReaderKeys() {
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.five, action: .pressed),
                on: .magnifier
            ),
            .magnifier(.switchCamera)
        )
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.six, action: .pressed),
                on: .liveTextReader
            ),
            .magnifier(.toggleTorch)
        )
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.seven, action: .pressed),
                on: .documentScanner
            ),
            .documentScanner(.capture)
        )
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.four, action: .pressed),
                on: .publicationReader
            ),
            .publicationReader(.previous)
        )
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.five, action: .pressed),
                on: .publicationReader
            ),
            .publicationReader(.togglePlayback)
        )
        XCTAssertEqual(
            RivoScreenRemoteMapper.action(
                for: button(.eight, action: .pressed),
                on: .publicationReader
            ),
            .publicationReader(.nextNavigationUnit)
        )
        XCTAssertNil(
            RivoScreenRemoteMapper.action(
                for: button(.seven, action: .released),
                on: .documentScanner
            )
        )
    }

    func testMagnifierDisplayModeRoutesAndroidDisplayKeys() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.magnifier)

        XCTAssertTrue(
            screenControl.receive(
                button(.l2, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.magnifierMode,
            .display
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .magnifier(
                .enterDisplayMode(showGuide: false)
            )
        )
        XCTAssertTrue(
            screenControl.receive(
                button(.four, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .magnifier(.previousColor)
        )
        XCTAssertTrue(
            screenControl.receive(
                button(.r2, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .magnifier(.invertColor)
        )

        XCTAssertTrue(
            screenControl.receive(
                button(.r1, action: .doubleTapped)
            )
        )
        XCTAssertEqual(
            screenControl.magnifierMode,
            .camera
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .magnifier(
                .enterCameraMode(showGuide: true)
            )
        )
        XCTAssertTrue(
            screenControl.receive(
                button(.r2, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .magnifier(.focus)
        )
    }

    func testMagnifierDisplayAdjustmentMatchesAndroidBounds() {
        var adjustment =
            MagnifierDisplayAdjustment.defaultValue

        adjustment = adjustment.updated(
            for: .previousColor
        )
        XCTAssertEqual(
            adjustment.colorIndex,
            LocalDocumentColorTheme.all.count - 1
        )
        adjustment = adjustment.updated(
            for: .nextColor
        )
        XCTAssertEqual(adjustment.colorIndex, 0)
        adjustment = adjustment.updated(
            for: .originalColor
        )
        XCTAssertNil(adjustment.colorIndex)

        for _ in 0 ..< 100 {
            adjustment = adjustment.updated(
                for: .increaseThreshold
            )
            adjustment = adjustment.updated(
                for: .increaseBrightness
            )
        }
        XCTAssertEqual(adjustment.threshold, 1.05)
        XCTAssertEqual(adjustment.brightness, 0.5)

        for _ in 0 ..< 200 {
            adjustment = adjustment.updated(
                for: .decreaseThreshold
            )
            adjustment = adjustment.updated(
                for: .decreaseBrightness
            )
        }
        XCTAssertEqual(adjustment.threshold, 0)
        XCTAssertEqual(adjustment.brightness, -0.5)

        adjustment = adjustment.updated(
            for: .resetThreshold
        )
        adjustment = adjustment.updated(
            for: .resetBrightness
        )
        adjustment = adjustment.updated(
            for: .invertColor
        )
        XCTAssertEqual(
            adjustment.threshold,
            MagnifierDisplayAdjustment
                .defaultThreshold
        )
        XCTAssertEqual(adjustment.brightness, 0)
        XCTAssertTrue(adjustment.isInverted)
    }

    func testMagnifierAndroidColorFilterRenders() {
        var adjustment =
            MagnifierDisplayAdjustment.defaultValue
        adjustment = adjustment.updated(
            for: .nextColor
        )
        let source = CIImage(
            color: CIColor(
                red: 0.4,
                green: 0.6,
                blue: 0.2
            )
        )
        .cropped(
            to: CGRect(
                x: 0,
                y: 0,
                width: 2,
                height: 2
            )
        )
        let output = adjustment.applying(to: source)

        XCTAssertNotNil(
            CIContext(
                options: [
                    .useSoftwareRenderer: true
                ]
            ).createCGImage(
                output,
                from: output.extent
            )
        )
    }

    func testScreenControlCenterPublishesRepeatedActions() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.publicationReader)

        XCTAssertTrue(
            screenControl.receive(
                button(.six, action: .pressed)
            )
        )
        let first = screenControl.latestEvent
        XCTAssertTrue(
            screenControl.receive(
                button(.six, action: .pressed)
            )
        )
        let second = screenControl.latestEvent

        XCTAssertEqual(
            first?.action,
            .publicationReader(.next)
        )
        XCTAssertEqual(
            second?.action,
            .publicationReader(.next)
        )
        XCTAssertNotEqual(first?.id, second?.id)
    }

    func testAIChatConsumesVoiceSequenceBeforeGlobalNavigation() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.localAIChat)

        XCTAssertTrue(
            screenControl.receivePriorityInput(
                .sequence("a/")
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localAIChat(.toggleVoiceInput)
        )
        XCTAssertFalse(
            screenControl.receivePriorityInput(
                button(.five, action: .pressed)
            )
        )
        XCTAssertTrue(
            screenControl.receivePriorityInput(
                button(.r3, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localAIChat(
                .toggleAnswerReading
            )
        )

        screenControl.deactivate(.localAIChat)
        XCTAssertFalse(
            screenControl.receivePriorityInput(
                .sequence("a/")
            )
        )
    }

    func testAIChatMapsSentenceReadingKeys() {
        let mappings: [
            (
                RivoButton,
                RivoLocalAIChatRemoteAction
            )
        ] = [
            (.four, .previousSentence),
            (.five, .replaySentence),
            (.six, .nextSentence),
            (.r3, .toggleAnswerReading),
        ]

        for (button, action) in mappings {
            XCTAssertEqual(
                RivoScreenRemoteMapper.action(
                    for: self.button(
                        button,
                        action: .pressed
                    ),
                    on: .localAIChat
                ),
                .localAIChat(action)
            )
        }
        XCTAssertNil(
            RivoScreenRemoteMapper.action(
                for: button(
                    .five,
                    action: .released
                ),
                on: .localAIChat
            )
        )
    }

    func testVoiceActionConsumesSecondSequenceAsCancel() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.voiceAction)

        XCTAssertTrue(
            screenControl.receivePriorityInput(
                .sequence("a/")
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .voiceAction(.cancel)
        )
    }

    func testLocalDocumentMapperMatchesAndroidTextViewMatrix() {
        let mappings: [
            (
                RivoButton,
                RivoLocalDocumentRemoteAction
            )
        ] = [
            (.one, .beginning),
            (.two, .previousLine),
            (.three, .previousPage),
            (.four, .decreaseFont),
            (.five, .defaultFont),
            (.six, .increaseFont),
            (.seven, .end),
            (.eight, .nextLine),
            (.nine, .nextPage),
            (.star, .decreaseLineHeight),
            (.zero, .defaultLineHeight),
            (.sharp, .increaseLineHeight),
        ]

        for (button, expectedAction) in mappings {
            XCTAssertEqual(
                RivoScreenRemoteMapper.action(
                    for: self.button(
                        button,
                        action: .pressed
                    ),
                    on: .localDocumentReader
                ),
                .localDocumentReader(
                    expectedAction
                )
            )
        }
    }

    func testLocalDocumentRemoteAppearanceClampsAndResets() {
        let minimum =
            LocalDocumentAppearance(
                fontLevel: 1,
                lineHeightLevel: 1,
                colorIndex: 0,
                showsLineSeparators: false
            )
        let maximum =
            LocalDocumentAppearance(
                fontLevel: 10,
                lineHeightLevel: 10,
                colorIndex: 0,
                showsLineSeparators: false
            )

        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .decreaseFont
                .updatedAppearance(
                    from: minimum
                )?.fontLevel,
            1
        )
        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .increaseLineHeight
                .updatedAppearance(
                    from: maximum
                )?.lineHeightLevel,
            10
        )
        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .defaultFont
                .updatedAppearance(
                    from: maximum
                )?.fontLevel,
            LocalDocumentAppearance
                .defaultValue.fontLevel
        )
        XCTAssertNil(
            RivoLocalDocumentRemoteAction
                .nextLine
                .updatedAppearance(
                    from: minimum
                )
        )
    }

    func testLocalDocumentRemoteColorActionsWrapAndInvert() {
        let first =
            LocalDocumentAppearance.defaultValue
        let lastIndex =
            LocalDocumentColorTheme.all.count - 1
        let last =
            LocalDocumentAppearance(
                fontLevel: 5,
                lineHeightLevel: 5,
                colorIndex: lastIndex,
                showsLineSeparators: false
            )

        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .previousColor
                .updatedAppearance(from: first)?
                .colorIndex,
            lastIndex
        )
        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .nextColor
                .updatedAppearance(from: last)?
                .colorIndex,
            0
        )
        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .invertColor
                .updatedAppearance(from: first)?
                .colorIndex,
            1
        )
        XCTAssertEqual(
            RivoLocalDocumentRemoteAction
                .originalColor
                .updatedAppearance(from: last)?
                .colorIndex,
            0
        )
    }

    func testLocalDocumentDisplayModeRoutesColorKeys() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.localDocumentReader)

        XCTAssertTrue(
            screenControl.receive(
                button(.l2, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.localDocumentMode,
            .display
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(
                .enterDisplayMode(showGuide: false)
            )
        )

        XCTAssertTrue(
            screenControl.receive(
                button(.four, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(.previousColor)
        )
        XCTAssertTrue(
            screenControl.receive(
                button(.r2, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(.invertColor)
        )

        XCTAssertTrue(
            screenControl.receive(
                button(.l3, action: .doubleTapped)
            )
        )
        XCTAssertEqual(
            screenControl.localDocumentMode,
            .text
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(
                .enterTextMode(showGuide: true)
            )
        )
        XCTAssertTrue(
            screenControl.receive(
                button(.four, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(.decreaseFont)
        )
    }

    func testLocalDocumentConsumesR3BeforeGlobalStop() {
        let screenControl =
            RivoScreenRemoteControlCenter()
        screenControl.activate(.localDocumentReader)

        XCTAssertTrue(
            screenControl.receivePriorityInput(
                button(.r3, action: .pressed)
            )
        )
        XCTAssertEqual(
            screenControl.latestEvent?.action,
            .localDocumentReader(.toggleReading)
        )
        XCTAssertFalse(
            screenControl.receivePriorityInput(
                button(.r3, action: .released)
            )
        )
    }

    func testQuickMenuKeepsButtonsFromScreenPriority() {
        XCTAssertFalse(
            RivoScreenInputPriorityPolicy
                .shouldOfferToScreenFirst(
                    button(.r3, action: .pressed),
                    isMenuPresented: true
                )
        )
        XCTAssertTrue(
            RivoScreenInputPriorityPolicy
                .shouldOfferToScreenFirst(
                    button(.r3, action: .pressed),
                    isMenuPresented: false
                )
        )
        XCTAssertTrue(
            RivoScreenInputPriorityPolicy
                .shouldOfferToScreenFirst(
                    .sequence("a/"),
                    isMenuPresented: true
                )
        )
    }

    private func button(
        _ button: RivoButton,
        action: RivoButtonAction
    ) -> RivoRemoteInput {
        .button(
            button: button,
            action: action,
            rawKey: 0
        )
    }
}
