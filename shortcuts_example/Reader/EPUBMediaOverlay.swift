import Foundation

nonisolated struct EPUBMediaOverlayItem:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let smilPath: String
    let textPath: String
    let textFragmentID: String?
    let audioPath: String
    let clipBeginSeconds: Double
    let clipEndSeconds: Double?
    let playOrder: Int?
}

nonisolated struct EPUBMediaOverlayParseResult:
    Equatable,
    Sendable
{
    let items: [EPUBMediaOverlayItem]
    let referencedTextPaths: [String]
}

nonisolated enum EPUBSMILClock {
    static func seconds(
        from rawValue: String?
    ) -> Double? {
        guard var value = rawValue?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased(),
              !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("npt=") {
            value.removeFirst(4)
        }
        if value.contains(":") {
            let parts = value.split(
                separator: ":",
                omittingEmptySubsequences: false
            )
            guard (2 ... 3).contains(
                parts.count
            ) else {
                return nil
            }
            let secondsPart = String(
                parts.last!
            ).replacingOccurrences(
                of: "s",
                with: ""
            )
            guard let seconds = Double(
                secondsPart
            ) else {
                return nil
            }
            if parts.count == 2 {
                guard let minutes = Double(
                    parts[0]
                ) else {
                    return nil
                }
                return max(
                    minutes * 60 + seconds,
                    0
                )
            }
            guard let hours = Double(parts[0]),
                  let minutes = Double(
                      parts[1]
                  ) else {
                return nil
            }
            return max(
                hours * 3_600
                    + minutes * 60
                    + seconds,
                0
            )
        }

        let multiplier: Double
        let number: String
        if value.hasSuffix("ms") {
            multiplier = 0.001
            number = String(value.dropLast(2))
        } else if value.hasSuffix("min") {
            multiplier = 60
            number = String(value.dropLast(3))
        } else if value.hasSuffix("h") {
            multiplier = 3_600
            number = String(value.dropLast())
        } else if value.hasSuffix("s") {
            multiplier = 1
            number = String(value.dropLast())
        } else {
            multiplier = 1
            number = value
        }
        guard let amount = Double(number) else {
            return nil
        }
        return max(amount * multiplier, 0)
    }
}

nonisolated enum EPUBMediaOverlayParser {
    static func parse(
        archive: EPUBArchive,
        paths: [String]
    ) -> [EPUBMediaOverlayItem] {
        parseResult(
            archive: archive,
            paths: paths
        ).items
    }

    static func parseResult(
        archive: EPUBArchive,
        paths: [String],
        fallbackTextDocumentPath:
            String? = nil
    ) -> EPUBMediaOverlayParseResult {
        var items: [EPUBMediaOverlayItem] = []
        var referencedTextPaths: [String] = []
        var seenTextPaths: Set<String> = []
        for path in paths
        where archive.contains(path) {
            guard let data = try? archive.data(
                at: path
            ) else {
                continue
            }
            let delegate = SMILXMLDelegate()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            guard parser.parse() else {
                continue
            }
            for rawItem in delegate.items {
                let text: ResolvedReference?
                if let source = rawItem.textSource,
                   !source.isEmpty {
                    text = try? resolve(
                        source,
                        relativeTo: path
                    )
                } else if let fallback =
                            fallbackTextDocumentPath,
                          archive.contains(fallback) {
                    text = ResolvedReference(
                        path: fallback,
                        fragment:
                            syntheticFragmentID(
                                smilPath: path,
                                itemID: rawItem.id
                            )
                    )
                } else {
                    text = nil
                }
                guard let text else {
                    continue
                }
                if archive.contains(text.path),
                   seenTextPaths
                    .insert(text.path).inserted {
                    referencedTextPaths.append(
                        text.path
                    )
                }
                guard let audioSource =
                        rawItem.audioSource,
                      !audioSource.isEmpty,
                      let audio =
                        try? resolve(
                            audioSource,
                            relativeTo: path
                        ),
                      archive.contains(
                          audio.path
                      ) else {
                    continue
                }
                items.append(
                    EPUBMediaOverlayItem(
                        id:
                            "\(path)#"
                            + rawItem.id,
                        smilPath: path,
                        textPath: text.path,
                        textFragmentID:
                            text.fragment,
                        audioPath: audio.path,
                        clipBeginSeconds:
                            EPUBSMILClock.seconds(
                                from:
                                    rawItem
                                    .clipBegin
                            ) ?? 0,
                        clipEndSeconds:
                            EPUBSMILClock.seconds(
                                from:
                                    rawItem
                                    .clipEnd
                            ),
                        playOrder:
                            rawItem.playOrder
                    )
                )
            }
        }
        return EPUBMediaOverlayParseResult(
            items: items,
            referencedTextPaths:
                referencedTextPaths
        )
    }

    private static func syntheticFragmentID(
        smilPath: String,
        itemID: String
    ) -> String {
        let seed = smilPath.map {
            $0.isLetter
                || $0.isNumber
                || "_.:-".contains($0)
                ? $0
                : "_"
        }
        return "__smil__\(String(seed))__\(itemID)"
    }

    private static func resolve(
        _ rawReference: String,
        relativeTo baseFilePath: String
    ) throws -> ResolvedReference {
        let pieces = rawReference.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let rawPath = pieces.first.map(
            String.init
        ) ?? ""
        let fragment = pieces.count > 1
            ? String(pieces[1])
                .removingPercentEncoding
            : nil
        let pathWithoutQuery = rawPath.split(
            separator: "?",
            maxSplits: 1
        ).first.map(String.init) ?? rawPath
        let baseDirectory = baseFilePath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let combined = baseDirectory.isEmpty
            ? pathWithoutQuery
            : "\(baseDirectory)/\(pathWithoutQuery)"
        return ResolvedReference(
            path: try EPUBArchive.normalizedPath(
                combined
            ),
            fragment:
                fragment?.isEmpty == false
                ? fragment
                : nil
        )
    }
}

private nonisolated struct ResolvedReference {
    let path: String
    let fragment: String?
}

private nonisolated final class SMILXMLDelegate:
    NSObject,
    XMLParserDelegate
{
    struct RawItem {
        let id: String
        let textSource: String?
        let audioSource: String?
        let clipBegin: String?
        let clipEnd: String?
        let playOrder: Int?
    }

    struct RawAudio {
        let id: String?
        let source: String
        let clipBegin: String?
        let clipEnd: String?
    }

    struct RawParallel {
        let id: String
        let playOrder: Int?
        var hasTextElement: Bool
        var textSource: String?
        var audios: [RawAudio]
    }

    private(set) var items: [RawItem] = []
    private var parallels: [RawParallel] = []
    private var parallelCounter = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict:
            [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "par":
            let id = attributeDict["id"]
                ?? "par-\(parallelCounter)"
            parallelCounter += 1
            parallels.append(
                RawParallel(
                    id: id,
                    playOrder: Int(
                        attributeDict[
                            "playOrder"
                        ]
                        ?? attributeDict[
                            "playorder"
                        ]
                        ?? ""
                    ),
                    hasTextElement: false,
                    textSource: nil,
                    audios: []
                )
            )
        case "text":
            guard !parallels.isEmpty else {
                return
            }
            let index = parallels.index(
                before:
                    parallels.endIndex
            )
            guard !parallels[index]
                    .hasTextElement else {
                return
            }
            parallels[index].hasTextElement = true
            if let source =
                    attributeDict["src"],
               !source.isEmpty {
                parallels[index].textSource =
                    source
            }
        case "audio":
            guard !parallels.isEmpty,
                  let source =
                    attributeDict["src"],
                  !source.isEmpty else {
                return
            }
            parallels[
                parallels.index(
                    before:
                        parallels.endIndex
                )
            ].audios.append(
                RawAudio(
                    id: attributeDict["id"],
                    source: source,
                    clipBegin:
                        attributeDict[
                            "clipBegin"
                        ]
                        ?? attributeDict[
                            "clip-begin"
                        ],
                    clipEnd:
                        attributeDict[
                            "clipEnd"
                        ]
                        ?? attributeDict[
                            "clip-end"
                        ]
                )
            )
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "par",
              let parallel = parallels.popLast() else {
            return
        }
        if parallel.audios.isEmpty {
            items.append(
                RawItem(
                    id: parallel.id,
                    textSource:
                        parallel.textSource,
                    audioSource: nil,
                    clipBegin: nil,
                    clipEnd: nil,
                    playOrder:
                        parallel.playOrder
                )
            )
            return
        }
        for (index, audio)
            in parallel.audios.enumerated() {
            items.append(
                RawItem(
                    id:
                        audio.id
                        ?? (
                            parallel.audios.count == 1
                            ? parallel.id
                            : "\(parallel.id)-audio-\(index)"
                        ),
                    textSource:
                        parallel.textSource,
                    audioSource: audio.source,
                    clipBegin:
                        audio.clipBegin,
                    clipEnd: audio.clipEnd,
                    playOrder:
                        parallel.playOrder
                        .map { $0 + index }
                )
            )
        }
    }
}
