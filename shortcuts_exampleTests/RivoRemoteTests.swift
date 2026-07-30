import Foundation
import XCTest

@testable import shortcuts_example

final class RivoRemoteProtocolTests: XCTestCase {
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

@MainActor
final class RivoRemoteControlCenterTests: XCTestCase {
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
            .navigate(.aiChat)
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
