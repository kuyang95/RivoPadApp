import Foundation

nonisolated enum RivoDeviceType:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case three
    case mini

    var title: String {
        switch self {
        case .three:
            return "Rivo Three"
        case .mini:
            return "Rivo Mini"
        }
    }

    static func from(serviceUUID: String) -> Self? {
        let compact = serviceUUID
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
        if compact == "f120"
            || compact.hasPrefix("0000f120") {
            return .three
        }
        if compact == "f121"
            || compact.hasPrefix("0000f121") {
            return .mini
        }
        return nil
    }
}

nonisolated struct RivoClockValue:
    Equatable,
    Sendable
{
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    let millisecond: Int
}

nonisolated enum RivoTimeSyncPacketEncoder {
    static func packet(
        for date: Date,
        calendar: Calendar = .current
    ) -> Data {
        let components =
            calendar.dateComponents(
                [
                    .year,
                    .month,
                    .day,
                    .hour,
                    .minute,
                    .second,
                    .nanosecond,
                ],
                from: date
            )
        return packet(
            for:
                RivoClockValue(
                    year:
                        components.year ?? 0,
                    month:
                        components.month ?? 0,
                    day: components.day ?? 0,
                    hour:
                        components.hour ?? 0,
                    minute:
                        components.minute ?? 0,
                    second:
                        components.second ?? 0,
                    millisecond:
                        (
                            components.nanosecond
                                ?? 0
                        ) / 1_000_000
                )
        )
    }

    static func packet(
        for value: RivoClockValue
    ) -> Data {
        var bytes =
            [UInt8](repeating: 0, count: 21)
        bytes[0] = ascii("A")
        bytes[1] = ascii("T")
        bytes[2] = ascii("D")
        bytes[3] = ascii("T")
        writeLittleEndian(
            11,
            into: &bytes,
            offset: 4
        )
        bytes[6] = 1
        bytes[7] = 0
        writeLittleEndian(
            value.year,
            into: &bytes,
            offset: 8
        )
        bytes[10] =
            UInt8(
                truncatingIfNeeded:
                    value.month
            )
        bytes[11] =
            UInt8(
                truncatingIfNeeded:
                    value.day
            )
        bytes[12] =
            UInt8(
                truncatingIfNeeded:
                    value.hour
            )
        bytes[13] =
            UInt8(
                truncatingIfNeeded:
                    value.minute
            )
        bytes[14] =
            UInt8(
                truncatingIfNeeded:
                    value.second
            )
        writeLittleEndian(
            value.millisecond,
            into: &bytes,
            offset: 15
        )

        let checksum =
            bytes[0 ..< 16].reduce(0) {
                partial, byte in
                partial
                    + Int(
                        Int8(bitPattern: byte)
                    )
            } & 0xFFFF
        writeLittleEndian(
            checksum,
            into: &bytes,
            offset: 17
        )
        bytes[19] = 0x0D
        bytes[20] = 0x0A
        return Data(bytes)
    }

    private static func writeLittleEndian(
        _ value: Int,
        into bytes: inout [UInt8],
        offset: Int
    ) {
        bytes[offset] =
            UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] =
            UInt8(
                truncatingIfNeeded:
                    value >> 8
            )
    }

    private static func ascii(
        _ character: Character
    ) -> UInt8 {
        character.asciiValue!
    }
}

nonisolated enum RivoButton:
    String,
    CaseIterable,
    Codable,
    Sendable
{
    case l1
    case l2
    case l3
    case l4
    case r1
    case r2
    case r3
    case r4
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case zero
    case star
    case sharp

    var title: String {
        switch self {
        case .l1:
            return "L1"
        case .l2:
            return "L2"
        case .l3:
            return "L3"
        case .l4:
            return "L4"
        case .r1:
            return "R1"
        case .r2:
            return "R2"
        case .r3:
            return "R3"
        case .r4:
            return "R4"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        case .six:
            return "6"
        case .seven:
            return "7"
        case .eight:
            return "8"
        case .nine:
            return "9"
        case .zero:
            return "0"
        case .star:
            return "별표"
        case .sharp:
            return "샵"
        }
    }
}

nonisolated enum RivoButtonAction:
    String,
    Codable,
    Sendable
{
    case pressed
    case released

    var title: String {
        switch self {
        case .pressed:
            return "누름"
        case .released:
            return "뗌"
        }
    }
}

nonisolated enum RivoRemoteInput: Equatable, Sendable {
    case button(
        button: RivoButton,
        action: RivoButtonAction,
        rawKey: UInt8
    )
    case sequence(String)

    var summary: String {
        switch self {
        case .button(let button, let action, _):
            return "\(button.title) \(action.title)"
        case .sequence(let payload):
            return "시퀀스 \(payload)"
        }
    }
}

nonisolated struct RivoPacketAssembler: Sendable {
    private static let startBytes = Data([0x61, 0x74])
    private static let headerAndTrailerSize = 10
    private static let maximumPacketSize = 65_545

    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else {
            return []
        }
        buffer.append(chunk)
        var packets: [Data] = []

        while true {
            guard alignToPacketStart() else {
                break
            }
            guard buffer.count >= 4 else {
                break
            }
            let signatureStart = buffer.index(
                buffer.startIndex,
                offsetBy: 2
            )
            let signatureEnd = buffer.index(
                after: signatureStart
            )
            guard buffer[signatureStart] == 0x42,
                  buffer[signatureEnd] == 0x54 else {
                buffer.removeFirst(2)
                continue
            }
            guard buffer.count
                    >= Self.headerAndTrailerSize else {
                break
            }

            let lengthLowIndex = buffer.index(
                buffer.startIndex,
                offsetBy: 4
            )
            let lengthHighIndex = buffer.index(
                after: lengthLowIndex
            )
            let payloadLength = Int(
                buffer[lengthLowIndex]
            ) | Int(buffer[lengthHighIndex]) << 8
            let packetLength = payloadLength
                + Self.headerAndTrailerSize
            guard packetLength <= Self.maximumPacketSize else {
                buffer.removeFirst(2)
                continue
            }
            guard buffer.count >= packetLength else {
                break
            }

            packets.append(
                Data(buffer.prefix(packetLength))
            )
            buffer.removeFirst(packetLength)
        }
        return packets
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func alignToPacketStart() -> Bool {
        guard let range = buffer.range(
            of: Self.startBytes
        ) else {
            if buffer.last == Self.startBytes.first {
                buffer = Data([Self.startBytes[0]])
            } else {
                buffer.removeAll(keepingCapacity: true)
            }
            return false
        }
        if range.lowerBound > buffer.startIndex {
            buffer.removeSubrange(
                buffer.startIndex ..< range.lowerBound
            )
        }
        return true
    }
}

nonisolated enum RivoRemotePacketParser {
    private static let pressKeys: [UInt8: RivoButton] = [
        ascii("-"): .l1,
        ascii("["): .l2,
        ascii(";"): .l3,
        ascii(","): .l4,
        ascii("="): .r1,
        ascii("]"): .r2,
        ascii("'"): .r3,
        ascii("\\"): .r4,
        ascii("1"): .one,
        ascii("2"): .two,
        ascii("3"): .three,
        ascii("4"): .four,
        ascii("5"): .five,
        ascii("6"): .six,
        ascii("7"): .seven,
        ascii("8"): .eight,
        ascii("9"): .nine,
        ascii("0"): .zero,
        ascii("."): .star,
        ascii("/"): .sharp
    ]

    private static let releaseKeys: [UInt8: RivoButton] = [
        ascii("_"): .l1,
        ascii("{"): .l2,
        ascii(":"): .l3,
        ascii("<"): .l4,
        ascii("+"): .r1,
        ascii("}"): .r2,
        ascii("\""): .r3,
        ascii("|"): .r4,
        ascii("!"): .one,
        ascii("@"): .two,
        ascii("#"): .three,
        ascii("$"): .four,
        ascii("%"): .five,
        ascii("^"): .six,
        ascii("&"): .seven,
        ascii("*"): .eight,
        ascii("("): .nine,
        ascii(")"): .zero,
        ascii(">"): .star,
        ascii("?"): .sharp
    ]

    static func parse(_ packet: Data) -> RivoRemoteInput? {
        let bytes = Array(packet)
        guard bytes.count >= 8,
              bytes[0] == ascii("a"),
              bytes[1] == ascii("t"),
              bytes[2] == ascii("B"),
              bytes[3] == ascii("T") else {
            return nil
        }

        switch bytes[6] {
        case 0:
            let key = bytes[7]
            if let button = pressKeys[key] {
                return .button(
                    button: button,
                    action: .pressed,
                    rawKey: key
                )
            }
            if let button = releaseKeys[key] {
                return .button(
                    button: button,
                    action: .released,
                    rawKey: key
                )
            }
            return nil
        case 2:
            let payloadSize = Int(bytes[7])
            guard payloadSize > 0,
                  bytes.count >= 8 + payloadSize else {
                return nil
            }
            let payloadData = Data(
                bytes[8 ..< 8 + payloadSize]
            )
            guard let payload = String(
                data: payloadData,
                encoding: .isoLatin1
            ) else {
                return nil
            }
            return .sequence(payload)
        default:
            return nil
        }
    }

    static func hex(_ data: Data) -> String {
        data.map {
            String(format: "%02X", $0)
        }
        .joined(separator: "-")
    }

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue!
    }
}
