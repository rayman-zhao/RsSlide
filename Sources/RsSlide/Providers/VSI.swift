import Foundation
import LibTIFF
import RsFoundation

/// Olympus cellSens slide: the `.vsi` file is a little-endian TIFF whose IFD 0
/// holds a JPEG overview of the glass slide.
struct VSIPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        #if os(Windows)
            guard let tiff = TIFFOpenW(fileInfo.mainPath.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(fileInfo.mainPath, "rh") else { return nil }
        #endif
        defer { TIFFClose(tiff) }

        return TIFFReadJPEGImage(tiff, 0)
    }
}

/// Random access to an `.ets` stack; offsets are absolute and can exceed
/// 2 GiB (FileHandle seek/read verified against such files on this toolchain).
private final class ETSFile {
    private let handle: FileHandle

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
    }

    deinit {
        try? handle.close()
    }

    func read(at offset: UInt64, count: Int) -> [UInt8]? {
        guard count > 0 else { return nil }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                return nil
            }
            return [UInt8](data)
        } catch {
            return nil
        }
    }
}

/// The metadata tree that starts at byte 8 of a `.vsi`: a chain of volumes,
/// each a 24-byte header plus field records linked by `nextField` offsets
/// relative to the volume header. Tag numbers only mean something relative to
/// their parent node, so query by path, never by a global tag search.
struct VSIMetadata {
    enum Value {
        case ints([Int])
        case doubles([Double])
        case text(String)
    }

    struct Node {
        var tag: Int
        var secondTag: Int?
        var children: [Node]
        var value: Value?

        func first(_ tag: Int) -> Node? {
            return children.first { $0.tag == tag }
        }

        func ints(_ tag: Int) -> [Int]? {
            return first(tag)?.ints
        }

        func doubles(_ tag: Int) -> [Double]? {
            return first(tag)?.doubles
        }

        func text(_ tag: Int) -> String? {
            return first(tag)?.text
        }

        var ints: [Int]? {
            if case .ints(let v)? = value { return v }
            return nil
        }

        var doubles: [Double]? {
            if case .doubles(let v)? = value { return v }
            return nil
        }

        var text: String? {
            if case .text(let v)? = value { return v }
            return nil
        }
    }

    let root: [Node]

    init?(data: Data) {
        var parser = Parser(bytes: [UInt8](data))
        guard let root = parser.volume(at: 8, depth: 0) else { return nil }
        self.root = root
    }

    private struct Parser {
        let bytes: [UInt8]
        var nodeBudget = 1 << 20

        static let newVolumeHeader = 0
        static let propertySetVolume = 1
        static let newMdimVolumeHeader = 2

        mutating func volume(at base: Int, depth: Int) -> [Node]? {
            guard depth < 32, nodeBudget > 0,
                u16(at: base) == 24, u16(at: base + 2) == 21321,
                let firstField = u64(at: base + 8), let flags = u32(at: base + 16)
            else { return nil }

            let count = Int(flags & 0xFFFFFFF)
            guard count <= bytes.count else { return nil }

            var nodes: [Node] = []
            var offset = Int(firstField)
            for _ in 0..<count {
                let pos = base + offset
                guard nodeBudget > 0, offset > 0, pos + 16 <= bytes.count,
                    let fieldType = i32(at: pos), let tag = i32(at: pos + 4),
                    let nextField = u32(at: pos + 8), let dataSize = i32(at: pos + 12),
                    tag >= 0
                else { break }

                let extraTag = (fieldType & 0x8000000) != 0
                let extended = (fieldType & 0x1000_0000) != 0
                let inlineData = (fieldType & 0x4000_0000) != 0
                let realType = Int(fieldType & 0xFFFFFF)

                var node = Node(
                    tag: Int(tag), secondTag: nil, children: [], value: nil)
                nodeBudget -= 1
                if extraTag, let second = i32(at: pos + 16) {
                    node.secondTag = Int(second)
                }
                let payload = pos + 16 + (extraTag ? 4 : 0)

                if extended {
                    if realType == Self.newVolumeHeader || realType == Self.propertySetVolume
                        || realType == Self.newMdimVolumeHeader
                    {
                        node.children = volume(at: payload, depth: depth + 1) ?? []
                    }
                } else if inlineData {
                    node.value = .ints([Int(dataSize)])
                } else if dataSize > 0 {
                    node.value = value(realType, at: payload, count: Int(dataSize))
                }

                nodes.append(node)
                if nextField == 0 { break }
                offset = Int(nextField)
            }
            return nodes
        }

        private func value(_ type: Int, at p: Int, count: Int) -> Value? {
            let len = max(0, min(count, bytes.count - p))
            guard len > 0 else { return nil }

            switch type {
            case 5, 6, 14, 256, 257, 258, 259, 267, 274, 275, 276, 277, 8195, 8199, 8200:
                var ints: [Int] = []
                var q = p
                while q + 4 <= p + len, ints.count < 4096 {
                    if let v = i32(at: q) { ints.append(Int(v)) }
                    q += 4
                }
                return ints.isEmpty ? nil : .ints(ints)
            case 10, 260, 261, 262, 263, 264, 265, 266, 268, 279, 280:
                var doubles: [Double] = []
                var q = p
                while q + 8 <= p + len, doubles.count < 4096 {
                    if let v = f64(at: q) { doubles.append(v) }
                    q += 8
                }
                return doubles.isEmpty ? nil : .doubles(doubles)
            default:
                return text(at: p, len: len).map { .text($0) }
            }
        }

        private static let trimSet = CharacterSet(charactersIn: "\0 ")

        /// Strings are UTF-16 when every other byte is zero, plain bytes
        /// otherwise (both encodings occur in the tree). Real tree strings are
        /// names and units, always small; anything larger is an annotation or
        /// vector payload that no consumer queries, so it is not decoded.
        private func text(at p: Int, len: Int) -> String? {
            guard len <= 4096 else { return nil }

            var utf16 = len >= 2 && len % 2 == 0
            if utf16 {
                for i in stride(from: p + 1, to: p + len, by: 2) where bytes[i] != 0 {
                    utf16 = false
                    break
                }
            }

            var s: String
            if utf16 {
                var units = [UInt16]()
                units.reserveCapacity(len / 2)
                var q = p
                while q + 1 < p + len {
                    units.append(UInt16(bytes[q]) | UInt16(bytes[q + 1]) << 8)
                    q += 2
                }
                s = String(decoding: units, as: UTF16.self)
            } else {
                s = String(bytes: bytes[p..<p + len], encoding: .utf8) ?? ""
            }
            let trimmed = s.trimmingCharacters(in: Self.trimSet)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func u16(at p: Int) -> Int? {
            guard p >= 0, p + 2 <= bytes.count else { return nil }
            return Int(bytes[p]) | Int(bytes[p + 1]) << 8
        }

        private func u32(at p: Int) -> UInt32? {
            guard p >= 0, p + 4 <= bytes.count else { return nil }
            return UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16
                | UInt32(bytes[p + 3]) << 24
        }

        private func u64(at p: Int) -> UInt64? {
            guard let low = u32(at: p), let high = u32(at: p + 4) else { return nil }
            return UInt64(low) | UInt64(high) << 32
        }

        private func i32(at p: Int) -> Int32? {
            return u32(at: p).map { Int32(bitPattern: $0) }
        }

        private func f64(at p: Int) -> Double? {
            guard let low = u32(at: p), let high = u32(at: p + 4) else { return nil }
            return Double(bitPattern: UInt64(low) | UInt64(high) << 32)
        }
    }
}

/// One `stackN/frame_*.ets` pixel stack: a 64-byte SIS envelope, a 228-byte
/// ETS header, the JPEG tile data, and a tile table at the end of the file
/// mapping (col, row, pyramid level) to a byte range. Tiles are not stored in
/// coordinate order, so every read goes through the table.
private struct ETSStack {
    struct Entry {
        var offset: UInt64
        var count: Int
    }

    struct Key: Hashable {
        var col: Int
        var row: Int
        var level: Int
    }

    let url: URL
    let pixelType: Int  // 2 = uint8
    let sizeC: Int
    let compression: Int  // 2 = JPEG in every slide file seen
    let tileW: Int
    let tileH: Int
    let width: Int  // extents from the ETS header
    let height: Int
    let backgroundRGB: Int
    let levels: [(w: Int, h: Int, r: Int, c: Int)]
    private let entries: [Key: Entry]

    init?(url: URL) {
        guard let handle = ETSFile(url: url) else { return nil }

        func read(_ offset: UInt64, _ count: Int) -> [UInt8]? {
            return handle.read(at: offset, count: count)
        }

        guard let sis = read(0, 64), sis.starts(with: [0x53, 0x49, 0x53]),
            let ndim = Self.u32(sis, 12), ndim >= 3, ndim <= 16,
            let etsOffset = Self.u64(sis, 16),
            let chunkOffset = Self.u64(sis, 32),
            let chunkCount = Self.u32(sis, 40), chunkCount > 0, chunkCount <= 1 << 24
        else { return nil }

        guard let ets = read(etsOffset, 228), ets.starts(with: [0x45, 0x54, 0x53]),
            let pixelType = Self.u32(ets, 8),
            let sizeC = Self.u32(ets, 12),
            let compression = Self.u32(ets, 20),
            let tileX = Self.u32(ets, 28), tileX > 0, tileX <= 4096,
            let tileY = Self.u32(ets, 32), tileY > 0, tileY <= 4096,
            let width = Self.u32(ets, 188), width > 0, width <= 1 << 24,
            let height = Self.u32(ets, 192), height > 0, height <= 1 << 24
        else { return nil }

        // Background color is sizeC bytes at ETS+108 (0xEE per channel in RGB
        // slides); read single bytes — a u32 read here would swallow the
        // neighbouring fields.
        var background = 0xFFFFFF
        if ets.count > 110 {
            background = Int(ets[108]) << 16 | Int(ets[109]) << 8 | Int(ets[110])
        }

        let stride = 4 * (Int(ndim) + 5)
        guard let table = read(chunkOffset, stride * Int(chunkCount)) else { return nil }

        var entries: [Key: Entry] = [:]
        var maxCols: [Int] = []
        var maxRows: [Int] = []
        var p = 0
        for _ in 0..<chunkCount {
            let coords = (0..<Int(ndim)).map {
                Int(Int32(bitPattern: Self.u32(table, p + 4 + $0 * 4) ?? 0))
            }
            let offset = Self.u64(table, p + 4 + Int(ndim) * 4) ?? 0
            let count = Self.u32(table, p + 12 + Int(ndim) * 4) ?? 0
            p += stride

            let key = Key(col: coords[0], row: coords[1], level: coords.last ?? -1)
            guard key.col >= 0, key.row >= 0, key.level >= 0, key.level < 32, count > 0 else {
                continue
            }
            entries[key] = Entry(offset: offset, count: Int(count))
            while maxCols.count <= key.level {
                maxCols.append(-1)
                maxRows.append(-1)
            }
            maxCols[key.level] = max(maxCols[key.level], key.col)
            maxRows[key.level] = max(maxRows[key.level], key.row)
        }
        guard let firstCol = maxCols.first, firstCol >= 0 else { return nil }

        var levels: [(w: Int, h: Int, r: Int, c: Int)] = []
        for level in 0..<maxCols.count {
            guard maxCols[level] >= 0 else { break }
            let c = maxCols[level] + 1
            let r = maxRows[level] + 1
            levels.append(
                (
                    min((Int(width) + (1 << level) - 1) >> level, c * Int(tileX)),
                    min((Int(height) + (1 << level) - 1) >> level, r * Int(tileY)),
                    r, c
                ))
        }

        self.url = url
        self.pixelType = Int(pixelType)
        self.sizeC = Int(sizeC)
        self.compression = Int(compression)
        self.tileW = Int(tileX)
        self.tileH = Int(tileY)
        self.width = Int(width)
        self.height = Int(height)
        self.backgroundRGB = background
        self.levels = levels
        self.entries = entries
    }

    func entry(col: Int, row: Int, level: Int) -> Entry? {
        return entries[Key(col: col, row: row, level: level)]
    }

    private static func u32(_ bytes: [UInt8], _ p: Int) -> UInt32? {
        guard p >= 0, p + 4 <= bytes.count else { return nil }
        return UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16
            | UInt32(bytes[p + 3]) << 24
    }

    private static func u64(_ bytes: [UInt8], _ p: Int) -> UInt64? {
        guard let low = u32(bytes, p), let high = u32(bytes, p + 4) else { return nil }
        return UInt64(low) | UInt64(high) << 32
    }
}

final class VSI: InternalSlide {
    private let mainStack: ETSStack
    private let stream: ETSFile
    private let tiff: OpaquePointer

    let fileInfo: SlideFileInfo
    let id: UUID
    let tierTrait = TierTrait()
    let channelTrait = [ChannelTrait()]
    let tileTrait: TileTrait

    let scanObjective: Double
    let scanScale: Double
    let extendedXML: String = ""

    let layerImageSize: [(w: Int, h: Int)]
    let layerTileSize: [(r: Int, c: Int)]

    lazy var topLayerPixelData = [fetchPixelData(at: layerTileSize.count - 1)]

    deinit {
        TIFFClose(tiff)
    }

    init?(path: URL) {
        fileInfo = SlideFileInfo(url: path)

        #if os(Windows)
            guard let tiff = TIFFOpenW(fileInfo.mainPath.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(fileInfo.mainPath, "rh") else { return nil }
        #endif
        self.tiff = tiff

        guard let data = try? Data(contentsOf: fileInfo.mainURL),
            let meta = VSIMetadata(data: data),
            let collection = meta.root.first(where: { $0.tag == 2000 })
        else { return nil }

        // One node per image: Label, Overview, and one or more main scans — a
        // slide may be scanned more than once (e.g. at 20x and 40x), each scan
        // an independent pyramid. The largest scan is the slide's pyramid.
        var scans: [(node: VSIMetadata.Node, id: Int, width: Int, height: Int)] = []
        for image in collection.children where image.tag == 2001 {
            guard let props = image.first(2005), let imageId = image.secondTag else { continue }

            var size = (w: 0, h: 0)
            for frame in image.children where frame.tag == 2002 {
                if let boundary = frame.first(2018)?.ints(2053), boundary.count == 4 {
                    size = (boundary[2], boundary[3])
                    break
                }
            }

            if (props.ints(2074)?.first ?? -1) == 0, size.w > 0, size.h > 0 {
                scans.append((image, imageId, size.w, size.h))
            }
        }

        let children = fileInfo.children
        let stackFile: (Int) -> URL? = { imageId in
            children.first { child in
                child.lastPathComponent.lowercased().hasPrefix("frame_")
                    && child.deletingLastPathComponent().lastPathComponent.lowercased()
                        == "stack\(imageId)"
            }
        }

        guard let main = scans.max(by: { $0.width * $0.height < $1.width * $1.height }),
            let mainStack = stackFile(main.id).flatMap({ ETSStack(url: $0) }),
            let stream = ETSFile(url: mainStack.url)
        else {
            log.warning("Cannot open cellSens main stack in \(fileInfo.mainPath)")
            return nil
        }
        guard mainStack.pixelType == 2, mainStack.sizeC == 3, mainStack.compression == 2 else {
            log.warning(
                "Unsupported cellSens main stack in \(fileInfo.mainPath): pixelType=\(mainStack.pixelType) sizeC=\(mainStack.sizeC) compression=\(mainStack.compression)"
            )
            return nil
        }
        if mainStack.width != main.width || mainStack.height != main.height {
            log.warning(
                "cellSens stack \(mainStack.url.lastPathComponent) extents \(mainStack.width)x\(mainStack.height) disagree with the metadata's \(main.width)x\(main.height) in \(fileInfo.mainPath)"
            )
        }
        self.mainStack = mainStack
        self.stream = stream

        let props = main.node.first(2005)
        scanScale = props?.doubles(2019)?.first ?? 0
        // The scanner prefixes scan names with the objective ("20x_BF_01");
        // the tree's magnification tag is empty in these files. Requiring the
        // trailing "x" keeps date-style names ("2026_03") from parsing as one.
        let scanName = props?.text(2030) ?? ""
        if let match = scanName.firstMatch(of: /^(\d+)[xX]/) {
            scanObjective = Double(match.1) ?? 0
        } else {
            scanObjective = 0
        }

        tileTrait = TileTrait(
            width: mainStack.tileW, height: mainStack.tileH,
            backgroundColorRGB: mainStack.backgroundRGB)
        layerImageSize = mainStack.levels.map { ($0.w, $0.h) }
        layerTileSize = mainStack.levels.map { ($0.r, $0.c) }

        let fingerprint = """
            dataSize: \(fileInfo.dataSize)
            scan: \(scanName)
            layers: \(layerImageSize)
            """
        id = Data(fingerprint.utf8).hashUUID
    }

    // The scanner embeds its camera snapshots as the leading TIFF directories
    // of the .vsi: IFD 0 is the whole-glass overview, IFD 1 the label photo.
    func fetchLabelJPEGImage() -> [UInt8]? {
        return TIFFReadJPEGImage(tiff, 1)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return TIFFReadJPEGImage(tiff, 0)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }
        guard let entry = mainStack.entry(col: coord.col, row: coord.row, level: coord.layer)
        else {
            // A complete grid is part of the format, so a missing tile means
            // a damaged stack.
            log.warning("Missing cellSens tile \(coord) in \(fileInfo.mainPath)")
            return nil
        }
        return stream.read(at: entry.offset, count: entry.count)
    }
}
