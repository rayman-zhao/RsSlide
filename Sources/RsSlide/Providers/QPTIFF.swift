import Foundation
import FoundationXML
import LibJPEGTurbo
import LibPNG
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

final class QPTIFF: InternalSlide {
    private let tiff: OpaquePointer
    private var channelLayerDir: [[UInt32]] = []

    private var tileCompression = COMPRESSION_JPEG
    private var macroDir: UInt32 = 0
    private var labelDir: UInt32 = 0
    private var imageDesc = ""
    private var imageWidth = 0
    private var imageHeight = 0
    private let quality = 85

    let fileInfo: SlideFileInfo

    var id: UUID = .zero
    let tierTrait = TierTrait()
    var channelTrait: [ChannelTrait] = []
    var tileTrait = TileTrait(width: 0, height: 0)

    var scanObjective = 0.0
    var scanScale = 0.0
    let extendedXML = ""

    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []
    var layerZoom = 2

    lazy var topLayerPixelData = (0..<channelTrait.count).map { i in
        fetchPixelData(at: layerTileSize.count - 1, channel: i)
    }

    init?(path: URL) {
        #if os(Windows)
            guard let tiff = TIFFOpenW(path.path.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(path.path, "rh") else { return nil }  // h - Read TIFF header only, do not load the first directory.
        #endif
        self.tiff = tiff

        fileInfo = SlideFileInfo(url: path)

        importDirectories()
        guard channelTrait.count > 0 && layerImageSize.count > 0 && tileTrait.size.w > 0 else {
            return nil
        }

        if id == .zero {
            let fingerprint = """
                dataSize: \(dataSize)
                imageDesc: \(imageDesc)
                layers: \(layerImageSize)
                channels: \(channelTrait.count)
                """
            id = Data(fingerprint.utf8).hashUUID
        }

        if layerTileSize.count > 1 {
            layerZoom = Int(ceil(Double(layerTileSize[0].r) / Double(layerTileSize[1].r)))
        }
    }

    deinit {
        TIFFClose(tiff)
    }

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
        guard TIFFSetDirectory(tiff, channelLayerDir[coord.channel][coord.layer]) else {
            return nil
        }

        let tileX = UInt32(coord.col * tileTrait.size.w)
        let tileY = UInt32(coord.row * tileTrait.size.h)
        let tid = TIFFComputeTile(tiff, tileX, tileY, 0, 0)
        let bufSize = tileTrait.maxBytes
        var buf = [UInt8](repeating: 0, count: bufSize)

        if tileCompression == COMPRESSION_JPEG {
            let tileSize = buf.withUnsafeMutableBytes {
                return Int(TIFFReadRawTile(tiff, tid, $0.baseAddress, tmsize_t(bufSize)))
            }
            guard tileSize > 0 else { return nil }
            buf.removeSubrange(tileSize...)
            return buf
        } else {
            let tileSize = buf.withUnsafeMutableBytes {
                return TIFFReadEncodedTile(tiff, tid, $0.baseAddress, tmsize_t(bufSize))
            }
            guard tileSize > 0 else { return nil }
            return pngCompress2(buf, .gray, tileTrait.size.w, tileTrait.size.h)
        }
    }

    private func importDirectories() {
        var mpp = -1.0

        while TIFFReadDirectory(tiff) == 1 {
            guard
                let desc: UnsafeMutablePointer<CChar> = TIFFGetField(tiff, TIFFTAG_IMAGEDESCRIPTION)
            else { continue }
            let text = String(cString: desc)
            if imageDesc.isEmpty {
                imageDesc = text
            }
            //  Document labelled UTF-16 but has UTF-8 content
            if let xml = try? XMLDocument(
                xmlString: text.replacingOccurrences(
                    of: "<?xml version=\"1.0\" encoding=\"utf-16\"?>",
                    with: "<?xml version=\"1.0\" encoding=\"utf-8\"?>"),
                options: .documentTidyXML)
            {
                importMetadata(from: xml)
            }

            if scanScale == 0.0 && mpp < 0,
                let res: Float = TIFFGetField(tiff, TIFFTAG_XRESOLUTION),
                let unit: UInt16 = TIFFGetField(tiff, TIFFTAG_RESOLUTIONUNIT)
            {
                if unit == RESUNIT_CENTIMETER {
                    mpp = Double(1 / res * 10 * 1000)
                } else if unit == RESUNIT_INCH {
                    mpp = Double(1 / res * 25.4 * 1000)
                }
            }
        }

        importLayers()
        // EasyScan 有很多不同的版本，输出校准值在不同的地方。
        if scanScale == 0.0 {
            scanScale = mpp > 0 ? mpp : 0.25 * 40 / max(scanObjective, 1)
        }
    }

    private func importMetadata(from xml: XMLDocument) {
        let dir = TIFFCurrentDirectory(tiff)
        var lastBand = -1

        xml.forEachElement { parent, name, _, value in
            guard let value else { return }

            switch name.lowercased() {
            case "imagetype":
                switch value.lowercased() {
                case "fullresolution" where imageWidth == 0 && imageHeight == 0:
                    if let compression: UInt16 = TIFFGetField(tiff, TIFFTAG_COMPRESSION),
                        let tw: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH),
                        let th: UInt32 = TIFFGetField(tiff, TIFFTAG_TILELENGTH)
                    {
                        tileCompression = Int32(compression)
                        tileTrait = TileTrait(
                            width: Int(tw), height: Int(th),
                            compression: tileCompression == COMPRESSION_JPEG ? .jpeg : .png,
                            pixelFormat: .gray, sampleBits: 8, backgroundColorRGB: 0)
                    }
                    if let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
                        let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
                    {
                        imageWidth = Int(w)
                        imageHeight = Int(h)
                    }
                case "overview" where macroDir == 0:
                    macroDir = dir
                case "label" where labelDir == 0:
                    labelDir = dir
                default:
                    break  // Thumbnail, ReducedResolution belongs to its band directories.
                }
            case "identifier" where id == .zero:
                if let v = UUID(uuidString: value) {
                    id = v
                }
            case "objective" where scanObjective == 0:
                // like 40X, 2.5X
                if let num = value.firstMatch(of: /^[\d.]+/)?.output,
                    let v = Double(num)
                {
                    scanObjective = v
                }
            case "pixelsizemicrons" where scanScale == 0.0:
                if let v = Double(value) {
                    scanScale = v
                }
            case "name":
                if let idx = channelTrait.firstIndex(where: { $0.name == value }) {
                    lastBand = idx
                } else {
                    channelTrait.append(ChannelTrait(name: value))
                    channelLayerDir.append([])

                    lastBand = channelTrait.count - 1
                }
                // Only the top-level <Name> of PerkinElmer-QPI-ImageDescription
                // marks this directory as a pyramid level of the band.
                if parent.lowercased().contains("imagedescription") {
                    channelLayerDir[lastBand].append(dir)
                }
            case "color" where lastBand >= 0:
                let parts = value.split(separator: ",").compactMap { Int($0) }
                if parts.count == 3 {
                    channelTrait[lastBand].pseudoColorRGB =
                        parts[0] << 16 | parts[1] << 8 | parts[2]
                }
            case "homewavelength" where lastBand >= 0:
                if let v = Int(value) {
                    channelTrait[lastBand].wavelength = v
                }
            default:
                break
            }
        }
    }

    private func importLayers() {
        guard let levelCount = channelLayerDir.map(\.count).min(), levelCount > 0 else { return }

        var (w, h) = (imageWidth, imageHeight)
        let (tw, th) = tileTrait.size

        for _ in 0..<levelCount {
            layerImageSize.append((w, h))
            layerTileSize.append(
                (
                    Int(
                        ceil(Double(h) / Double(th))
                    ),
                    Int(
                        ceil(Double(w) / Double(tw))
                    )
                )
            )

            w /= 2
            h /= 2
        }

    }
}
