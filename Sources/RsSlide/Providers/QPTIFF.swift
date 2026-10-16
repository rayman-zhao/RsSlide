import Foundation
import FoundationXML
import LibJPEGTurbo
import LibTIFF
import RsFoundation

struct QPTIFFPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        #if os(Windows)
            let tiff = TIFFOpenW(fileInfo.mainPath.wideString, "rh")
        #else
            let tiff = TIFFOpen(fileInfo.mainPath, "rh")
        #endif
        guard tiff != nil else { return nil }
        defer {
            TIFFClose(tiff)
        }

        let dirCount = TIFFNumberOfDirectories(tiff)
        guard dirCount > 1 else { return nil }
        if let macro = TIFFReadJPEGImage(tiff, dirCount - 1) {
            return macro
        }

        // Search for first strip image directory, which is usually the thumbnail image.
        for dirnum in 1..<(dirCount - 1) {
            if let thumbnail = TIFFReadJPEGImage(tiff, dirnum) {
                return thumbnail
            }
        }

        return nil
    }
}

private struct QPTIFFBand {
    var name = ""
    var color = (r: 0, g: 0, b: 0)
    var wavelength = 0
    var directories: [UInt32] = []
}

final class QPTIFF: InternalSlide {
    private let tiff: OpaquePointer
    private var bands: [QPTIFFBand] = []
    private var bandIndexByName: [String: Int] = [:]
    private var macroDir: UInt32 = 0
    private var labelDir: UInt32 = 0
    private var imageDesc = ""
    private var quality = 85

    let fileInfo: SlideFileInfo

    lazy var id: UUID = {
        let fingerprint = """
            dataSize: \(dataSize)
            imageDesc: \(imageDesc)
            layers: \(layerImageSize)
            tiers: \(bands.count)
            """

        return Data(fingerprint.utf8).hashUUID
    }()
    var scanObjective = 0
    var scanScale = 0.0
    var tierCount: Int { bands.count }
    let tierSpacing: Double = 0.0
    var channelCount: Int = 1
    var tileTrait = TileTrait(width: 0, height: 0)
    var layerZoom = 2
    var extendedXML = ""

    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []

    lazy var topLayerPixelData = [fetchPixelData(at: layerTileSize.count - 1)]

    init?(path: URL) {
        #if os(Windows)
            guard let tiff = TIFFOpenW(path.path.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(path.path, "rh") else { return nil }  // h - Read TIFF header only, do not load the first directory.
        #endif
        self.tiff = tiff

        fileInfo = SlideFileInfo(url: path)

        importDirectories()
        importLayers()

        guard bands.count > 0, tileTrait.size.w > 0, !layerImageSize.isEmpty else { return nil }

        if layerTileSize.count > 1 {
            layerZoom = Int(ceil(Double(layerTileSize[0].r) / Double(layerTileSize[1].r)))
        }

        // Same fallback chain as the old C++ reader.
        if scanScale == 0.0 {
            scanScale = 0.25 * 40 / Double(max(scanObjective, 1))
        }

        extendedXML = buildScanProfileXML()
    }

    deinit {
        TIFFClose(tiff)
    }

    /// TIFF directory indices per band, exposed for tests and debugging.
    var bandDirectories: [[UInt32]] { bands.map(\.directories) }

    func fetchLabelJPEGImage() -> [UInt8]? {
        guard labelDir != 0 else { return nil }
        return TIFFReadJPEGImage(tiff, labelDir)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        guard macroDir != 0 else { return nil }
        return TIFFReadJPEGImage(tiff, macroDir)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }
        guard coord.tier < bands.count else { return nil }
        let directories = bands[coord.tier].directories
        guard coord.layer < directories.count else { return nil }
        guard TIFFSetDirectory(tiff, directories[coord.layer]) else { return nil }

        let tileX = UInt32(coord.col * tileTrait.size.w)
        let tileY = UInt32(coord.row * tileTrait.size.h)
        let tid = TIFFComputeTile(tiff, tileX, tileY, 0, 0)

        // The JPEG tiles reference shared JPEGTables and Q-Scan6 writes LZW, so the raw
        // bytes are never standalone images. Decode via libtiff and re-encode mono JPEG.
        let bufSize = tileTrait.maxBytes
        var buf = [UInt8](repeating: 0, count: bufSize)
        guard TIFFReadEncodedTile(tiff, tid, &buf, tmsize_t(bufSize)) > 0 else { return nil }
        return tjCompress(buf, tileTrait.tjPF, tileTrait.size.w, tileTrait.size.h, 0, quality)
    }

    private func importDirectories() {
        var mpp = -1.0

        while TIFFReadDirectory(tiff) == 1 {
            let dir = TIFFCurrentDirectory(tiff)

            if mpp < 0,
                let res: Float = TIFFGetField(tiff, TIFFTAG_XRESOLUTION),
                let unit: UInt16 = TIFFGetField(tiff, TIFFTAG_RESOLUTIONUNIT)
            {
                if unit == RESUNIT_CENTIMETER {
                    mpp = Double(1 / res * 10 * 1000)
                } else if unit == RESUNIT_INCH {
                    mpp = Double(1 / res * 25.4 * 1000)
                }
            }

            guard
                let desc: UnsafeMutablePointer<CChar> = TIFFGetField(
                    tiff, TIFFTAG_IMAGEDESCRIPTION),
                let text = Self.decodeImageDescription(desc)
            else { continue }

            if imageDesc.isEmpty { imageDesc = text }
            guard let xml = try? XMLDocument(xmlString: Self.normalizeXML(text)) else { continue }

            var elements: [(parent: String, name: String, text: String)] = []
            if let root = xml.rootElement() {
                Self.collectElements(root, parent: "", into: &elements)
            }

            var lastBand = -1
            for e in elements {
                switch e.name.lowercased() {
                case "imagetype":
                    switch e.text.lowercased() {
                    case "fullresolution":
                        if tileTrait.size.w == 0 { importTileTrait() }
                    case "overview":
                        if macroDir == 0 { macroDir = dir }
                    case "label":
                        if labelDir == 0 { labelDir = dir }
                    default:
                        break  // Thumbnail, ReducedResolution belongs to its band directories.
                    }
                case "objective" where scanObjective == 0:
                    scanObjective = Int(e.text.prefix(while: \.isNumber)) ?? 0
                case "pixelsizemicrons" where scanScale == 0.0:
                    scanScale = Double(e.text) ?? 0.0
                case "name":
                    if let idx = bandIndexByName[e.text] {
                        lastBand = idx
                    } else {
                        bands.append(QPTIFFBand(name: e.text))
                        lastBand = bands.count - 1
                        bandIndexByName[e.text] = lastBand
                    }
                    // Only the top-level <Name> of PerkinElmer-QPI-ImageDescription
                    // marks this directory as a pyramid level of the band.
                    if e.parent.lowercased().contains("imagedescription") {
                        bands[lastBand].directories.append(dir)
                    }
                case "color" where lastBand >= 0:
                    let parts = e.text.split(separator: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespaces))
                    }
                    if parts.count == 3 {
                        bands[lastBand].color = (parts[0], parts[1], parts[2])
                    }
                case "homewavelength" where lastBand >= 0:
                    bands[lastBand].wavelength = Int(e.text) ?? 0
                default:
                    break
                }
            }
        }

        if scanScale == 0.0 && mpp > 0 {
            scanScale = mpp
        }
    }

    private func importTileTrait() {
        if let tw: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH),
            let th: UInt32 = TIFFGetField(tiff, TIFFTAG_TILELENGTH)
        {
            tileTrait = TileTrait(
                width: Int(tw), height: Int(th), pixelFormat: .gray, sampleBits: 8,
                backgroundColorRGB: 0)
        }
    }

    private func importLayers() {
        guard let levelCount = bands.map(\.directories.count).min(), levelCount > 0 else { return }

        // Defensive trim when a corrupt file gives some bands fewer levels than others.
        for i in bands.indices where bands[i].directories.count > levelCount {
            bands[i].directories.removeSubrange(levelCount...)
        }

        for level in 0..<levelCount {
            guard TIFFSetDirectory(tiff, bands[0].directories[level]) else { continue }
            guard let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
                let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
            else { continue }

            layerImageSize.append((Int(w), Int(h)))
            layerTileSize.append(
                (
                    Int(ceil(Double(h) / Double(tileTrait.size.h))),
                    Int(ceil(Double(w) / Double(tileTrait.size.w)))
                ))
        }
    }

    private func buildScanProfileXML() -> String {
        var xml = "<ScanProfile>\n\t<Bands>\n"
        for band in bands {
            let argb = 0xFF00_0000 | band.color.r << 16 | band.color.g << 8 | band.color.b
            xml += "\t\t<Band>\n"
            xml += "\t\t\t<Name>\(band.name)</Name>\n"
            xml += "\t\t\t<Color>\(String(argb))</Color>\n"
            xml += "\t\t\t<HomeWavelength>\(band.wavelength)</HomeWavelength>\n"
            xml += "\t\t</Band>\n"
        }
        xml += "\t</Bands>\n</ScanProfile>"
        return xml
    }

    /// The QPTIFF vendors declare `encoding="utf-16"` but almost always write ASCII,
    /// so the raw bytes decide the real encoding, not the declaration.
    private static func decodeImageDescription(_ desc: UnsafeMutablePointer<CChar>) -> String? {
        let b0 = UInt8(bitPattern: desc[0])
        let b1 = UInt8(bitPattern: desc[1])
        if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
            var length = 2
            while length + 1 < (1 << 20) && !(desc[length] == 0 && desc[length + 1] == 0) {
                length += 2
            }
            let data = Data(bytes: desc, count: length)
            return String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .utf16LittleEndian)
        }
        return String(validatingCString: desc)
    }

    /// Windows FoundationXML throws on any declared encoding other than utf-8.
    private static func normalizeXML(_ xml: String) -> String {
        xml.replacingOccurrences(
            of: #"<\?xml[^>]*\?>"#,
            with: "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            options: .regularExpression)
    }

    private static func collectElements(
        _ element: XMLElement, parent: String,
        into output: inout [(parent: String, name: String, text: String)]
    ) {
        let name = element.name ?? ""
        output.append((parent, name, element.stringValue ?? ""))
        for case let child as XMLElement in element.children ?? [] {
            collectElements(child, parent: name, into: &output)
        }
    }
}
