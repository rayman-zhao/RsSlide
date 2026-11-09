import Foundation
import LibJPEGTurbo
import LibTIFF
import LittleCMS
import RsFoundation

struct SVSPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        withTIFF { return TIFFReadJPEGStrip($0, $1) }
    }

    func fetchMacroRGBAImage() -> RGBAImage? {
        withTIFF { return TIFFReadRGBAStrip($0, $1) }
    }

    private func withTIFF<T>(_ body: (OpaquePointer, UInt32) -> T?) -> T? {
        #if os(Windows)
            guard let tiff = TIFFOpenW(fileInfo.mainPath.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(fileInfo.mainPath, "rh") else { return nil }
        #endif
        defer { TIFFClose(tiff) }

        // Directory count may be 0 when the file is a stripped/corrupt TIFF without directories.
        let dirCount = TIFFNumberOfDirectories(tiff)
        guard dirCount > 0 else { return nil }
        return body(tiff, dirCount - 1) ?? body(tiff, 1)
    }
}

final class SVS: InternalSlide {
    private let tiff: OpaquePointer
    private var layerDir: [UInt32] = []
    private var tilePhotometric = 0
    private var macroDir: UInt32 = 0
    private var labelDir: UInt32 = 0
    private var imageDesc = ""
    private var quality = 85
    private var gamma: Double?
    private var cmsTransform: cmsHTRANSFORM?

    // Plain strip TIFF (directory 0 is stripped): it is the only layer,
    // decoded whole into the single whole-image cache that synthetic 512x512
    // tiles and topLayerPixelData are cut from.
    private var stripDir: UInt32?
    private lazy var stripLayer: LayerPixelData? = decodeStripLayer()

    let fileInfo: SlideFileInfo

    lazy var id: UUID = {
        let fingerprint = """
            dataSize: \(dataSize)
            imageDesc: \(imageDesc)
            layers: \(layerImageSize)
            """

        return Data(fingerprint.utf8).hashUUID
    }()
    let tierTrait = TierTrait()
    let channelTrait = [ChannelTrait()]
    var tileTrait: TileTrait = TileTrait(width: 0, height: 0)

    var scanObjective = 0.0
    var scanScale = 0.0
    let extendedXML: String = ""

    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []

    lazy var topLayerPixelData = [
        stripLayer ?? fetchPixelData(at: layerTileSize.count - 1)
    ]

    init?(path: URL) {
        #if os(Windows)
            guard let tiff = TIFFOpenW(path.path.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(path.path, "rh") else { return nil }  // h - Read TIFF header only, do not load the first directory.
        #endif
        self.tiff = tiff

        fileInfo = SlideFileInfo(url: path)

        importDirectories()
        guard layerImageSize.count > 0 && tileTrait.size.w > 0 && tileTrait.size.h > 0 else {
            return nil
        }
    }

    deinit {
        TIFFClose(tiff)
        if let cmsTransform {
            cmsDeleteTransform(cmsTransform)
        }
    }

    func fetchLabelJPEGImage() -> [UInt8]? {
        guard labelDir != 0 else { return nil }
        return TIFFReadJPEGStrip(tiff, labelDir)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        guard macroDir != 0 else { return nil }
        return TIFFReadJPEGStrip(tiff, macroDir)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }
        guard stripDir == nil else { return fetchStripTileImage(for: coord) }

        guard TIFFSetDirectory(tiff, layerDir[coord.layer]) else { return nil }

        let tileX = UInt32(coord.col * tileTrait.size.w)
        let tileY = UInt32(coord.row * tileTrait.size.h)

        if let cmsTransform {
            let bufSize = tileTrait.size.w * tileTrait.size.h
            var buf = [UInt32](repeating: 0, count: bufSize)
            guard TIFFReadRGBATile(tiff, tileX, tileY, &buf) > 0 else { return nil }

            var buf2 = [UInt32](repeating: 0, count: bufSize)
            cmsDoTransform(cmsTransform, buf, &buf2, cmsUInt32Number(bufSize))

            let jpg = tjCompress(
                buf2, TJPF_RGBA, tileTrait.size.w, tileTrait.size.h, 0, quality, true)
            return jpg
        }

        let tid = TIFFComputeTile(tiff, tileX, tileY, 0, 0)
        let bufSize = tileTrait.maxBytes
        var buf = [UInt8](repeating: 0, count: bufSize)
        if tilePhotometric == PHOTOMETRIC_RGB {
            let tileSize = Int(TIFFReadEncodedTile(tiff, tid, &buf, tmsize_t(bufSize)))
            guard tileSize > 0 else { return nil }
            return tjCompress(buf, tileTrait.tjPF, tileTrait.size.w, tileTrait.size.h, 0, quality)
        } else {
            let tileSize = Int(TIFFReadRawTile(tiff, tid, &buf, tmsize_t(bufSize)))
            guard tileSize > 0 else { return nil }
            return Array(buf[..<tileSize])
        }
    }

    private func importDirectories() {
        #if os(macOS)
            let bufSize = 128 * 1024
            var buf = [UInt8](repeating: 0, count: bufSize)
            let fp = fmemopen(&buf, bufSize, "w")
            defer { fclose(fp) }
        #endif

        while TIFFReadDirectory(tiff) == 1 {
            let dir = TIFFCurrentDirectory(tiff)
            // Accoording to openslide comments, "NewSubfileType 1 for the label associated image, 9 for the macro associated image"
            // So that the label image also be "reduced" image, thus have to use the tile size to help.
            let tw: UInt32? = TIFFGetField(tiff, TIFFTAG_TILEWIDTH)

            if dir == 0 {  // First directory always be bottom layer image.
                if tw != nil {
                    importMetadata(from: dir)
                    importLayer(from: dir)
                } else {
                    importStrip(from: dir)
                }
            } else if tw != nil {  // Sequential reduced layer image.
                importLayer(from: dir)
            } else if dir == 1 {
                // Ignore second non-reduced directory, should be thumbnail image.
            } else if labelDir == 0,
                let desc: UnsafeMutablePointer<CChar> = TIFFGetField(
                    tiff, TIFFTAG_IMAGEDESCRIPTION),
                String(cString: desc).lowercased().contains("label")
            {
                labelDir = dir
            } else if macroDir == 0,
                let desc: UnsafeMutablePointer<CChar> = TIFFGetField(
                    tiff, TIFFTAG_IMAGEDESCRIPTION),
                String(cString: desc).lowercased().contains("macro")
            {
                macroDir = dir
            } else if labelDir == 0 && TIFFLastDirectory(tiff) == 0 {  // Second last directory, should be label image.
                labelDir = dir
            } else if macroDir == 0 && TIFFLastDirectory(tiff) == 1 {  // Last directory, should be macro image.
                macroDir = dir
            }

            #if os(macOS)
                fputs("Directory \(dir)\n", fp)
                TIFFPrintDirectory(tiff, fp, 0)
            #endif
        }

        #if os(macOS)
            fflush(fp)
            if let str = String(utf8String: buf) {
                log.info("\n\(str)")
            }
        #endif
    }

    private func importMetadata(from dir: UInt32) {
        if let tw: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH),
            let th: UInt32 = TIFFGetField(tiff, TIFFTAG_TILELENGTH)
        {
            tileTrait = TileTrait(width: Int(tw), height: Int(th))
        }
        if let photometric: UInt16 = TIFFGetField(tiff, TIFFTAG_PHOTOMETRIC) {
            tilePhotometric = Int(photometric)
        }

        if let desc: UnsafeMutablePointer<CChar> = TIFFGetField(tiff, TIFFTAG_IMAGEDESCRIPTION) {  // libtiff keep this const char * memory
            imageDesc = String(cString: desc)

            let scn = Scanner(string: String(cString: desc))

            if scn.scanUpToString("AppMag") != nil,
                scn.scanString("AppMag") != nil,
                scn.scanString("=") != nil,
                let v = scn.scanDouble()
            {
                scanObjective = v
            }

            scn.currentIndex = scn.string.startIndex
            if scn.scanUpToString("MPP") != nil,
                scn.scanString("MPP") != nil,
                scn.scanString("=") != nil,
                let v = scn.scanDouble()
            {
                scanScale = v
            }

            scn.currentIndex = scn.string.startIndex
            if scn.scanUpToString("Q") != nil,
                scn.scanString("Q") != nil,
                scn.scanString("=") != nil,
                let v = scn.scanInt()
            {
                quality = v
            }

            scn.currentIndex = scn.string.startIndex
            if scn.scanUpToString("Gamma") != nil,
                scn.scanString("Gamma") != nil,
                scn.scanString("=") != nil,
                let v = scn.scanDouble()
            {
                gamma = v
            }
        }

        let icc: (count: UInt32?, data: UnsafeMutableRawPointer?) = TIFFGetField(
            tiff, TIFFTAG_ICCPROFILE)
        if let iccCount = icc.count,
            let iccData = icc.data,
            let iccProfile = cmsOpenProfileFromMem(iccData, iccCount)
        {
            defer { cmsCloseProfile(iccProfile) }

            if cmsGetColorSpace(iccProfile) == cmsSigRgbData {
                let sRGB = cmsCreate_sRGBProfile()!
                defer { cmsCloseProfile(sRGB) }

                cmsTransform = cmsCreateTransform(
                    iccProfile, CMS_TYPE_RGBA_8, sRGB, CMS_TYPE_RGBA_8,
                    cmsUInt32Number(INTENT_PERCEPTUAL), 0)
            } else {
                log.warning("ICC profile color space is not RGB, ignored")
            }
        }

        if scanScale == 0.0,
            let res: Float = TIFFGetField(tiff, TIFFTAG_XRESOLUTION),
            let unit: UInt16 = TIFFGetField(tiff, TIFFTAG_RESOLUTIONUNIT)
        {
            if unit == RESUNIT_CENTIMETER {
                scanScale = Double(1 / res * 10 * 1000)
            } else if unit == RESUNIT_INCH {
                scanScale = Double(1 / res * 25.4 * 1000)
            }
        }

        if scanObjective == 0 {
            switch scanScale {
            case 0.15...0.35:
                scanObjective = 40
            case 0.4...0.6:
                scanObjective = 20
            case 0.9...1.1:
                scanObjective = 10
            default:
                break
            }
        }
    }

    private func importLayer(from dir: UInt32) {
        if let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
            let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
        {
            layerDir.append(dir)
            layerImageSize.append((Int(w), Int(h)))
            layerTileSize.append(
                (
                    Int(ceil(Double(h) / Double(tileTrait.size.h))),
                    Int(ceil(Double(w) / Double(tileTrait.size.w)))
                ))
        }
    }

    private func importStrip(from dir: UInt32) {
        guard let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
            let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
        else { return }

        stripDir = dir
        tileTrait = TileTrait(width: 512, height: 512)
        layerImageSize.append((Int(w), Int(h)))
        layerTileSize.append(
            (
                Int(ceil(Double(h) / Double(tileTrait.size.h))),
                Int(ceil(Double(w) / Double(tileTrait.size.w)))
            ))

        if let res: Float = TIFFGetField(tiff, TIFFTAG_XRESOLUTION),
            let unit: UInt16 = TIFFGetField(tiff, TIFFTAG_RESOLUTIONUNIT)
        {
            if unit == RESUNIT_CENTIMETER {
                scanScale = Double(1 / res * 10 * 1000)
            } else if unit == RESUNIT_INCH {
                scanScale = Double(1 / res * 25.4 * 1000)
            }
        }
        switch scanScale {
        case 0.15...0.35:
            scanObjective = 40
        case 0.4...0.6:
            scanObjective = 20
        case 0.9...1.1:
            scanObjective = 10
        default:
            break
        }
    }

    private func fetchStripTileImage(for coord: TileCoordinate) -> [UInt8]? {
        guard let strip = stripLayer else { return nil }

        let pixelBytes = tileTrait.pixelBytes
        let tileX = coord.col * tileTrait.size.w
        let tileY = coord.row * tileTrait.size.h
        let tileWidth = min(tileTrait.size.w, strip.width - tileX)
        let tileHeight = min(tileTrait.size.h, strip.height - tileY)
        let rowBytes = tileWidth * pixelBytes
        var pixels = [UInt8](repeating: 0, count: rowBytes * tileHeight)

        for row in 0..<tileHeight {
            let srcStart = (tileY + row) * strip.pitch + tileX * pixelBytes
            pixels[(row * rowBytes)..<((row + 1) * rowBytes)] =
                strip.pixels[srcStart..<(srcStart + rowBytes)]
        }

        return tjCompress(pixels, tileTrait.tjPF, tileWidth, tileHeight, 0, quality)
    }

    /// The single whole-image cache: tile fetches and `topLayerPixelData` both
    /// cut from it, so the strip layer lives in memory exactly once.
    private func decodeStripLayer() -> LayerPixelData? {
        guard let stripDir, TIFFSetDirectory(tiff, stripDir) else { return nil }

        let w = layerImageSize[0].w
        let h = layerImageSize[0].h

        // Chunky 8-bit RGB strips decode straight into the final buffer; every
        // other storage (gray/palette/YCbCr/planar/…) falls back to the RGBA
        // interface below, which normalizes photometrics at the cost of a
        // whole-image RGBA intermediate.
        let photometric: UInt16? = TIFFGetField(tiff, TIFFTAG_PHOTOMETRIC)
        let samples: UInt16? = TIFFGetField(tiff, TIFFTAG_SAMPLESPERPIXEL)
        let bits: UInt16? = TIFFGetField(tiff, TIFFTAG_BITSPERSAMPLE)
        let planar: UInt16? = TIFFGetField(tiff, TIFFTAG_PLANARCONFIG)
        let orientation: UInt16? = TIFFGetField(tiff, TIFFTAG_ORIENTATION)
        if photometric == UInt16(PHOTOMETRIC_RGB), samples == 3, bits == 8,
            planar == nil || planar == UInt16(PLANARCONFIG_CONTIG),
            orientation == nil || orientation == UInt16(ORIENTATION_TOPLEFT)
        {
            var pixels = [UInt8](repeating: 0, count: w * h * 3)
            let decoded = pixels.withUnsafeMutableBytes { buf -> Int in
                var offset = 0
                for strip in 0..<TIFFNumberOfStrips(tiff) {
                    let n = TIFFReadEncodedStrip(
                        tiff, strip, buf.baseAddress! + offset, tmsize_t(buf.count - offset))
                    guard n > 0 else { return -1 }
                    offset += Int(n)
                }
                return offset
            }
            if decoded >= 0 {
                return LayerPixelData(
                    pixels: pixels, layer: 0, width: w, pitch: w * 3, height: h)
            }
            return nil
        }

        var raster = [UInt8](repeating: 0, count: w * h * 4)
        guard
            raster.withUnsafeMutableBytes({
                TIFFReadRGBAImageOriented(
                    tiff, UInt32(w), UInt32(h),
                    $0.baseAddress?.assumingMemoryBound(to: UInt32.self),
                    ORIENTATION_TOPLEFT, 0) == 1
            })
        else { return nil }

        // libtiff RGBA raster words are 0xAABBGGRR in host (little-endian) order.
        // Compact to RGB in place — the write front 3i never overtakes the read
        // word 4i — then drop the tail instead of allocating a second buffer.
        raster.withUnsafeMutableBytes { raw in
            for i in 0..<(w * h) {
                let v = raw.load(fromByteOffset: i * 4, as: UInt32.self)
                raw.storeBytes(
                    of: UInt8(truncatingIfNeeded: v), toByteOffset: i * 3, as: UInt8.self)
                raw.storeBytes(
                    of: UInt8(truncatingIfNeeded: v >> 8), toByteOffset: i * 3 + 1,
                    as: UInt8.self)
                raw.storeBytes(
                    of: UInt8(truncatingIfNeeded: v >> 16), toByteOffset: i * 3 + 2,
                    as: UInt8.self)
            }
        }
        raster.removeLast(w * h)

        return LayerPixelData(pixels: raster, layer: 0, width: w, pitch: w * 3, height: h)
    }
}
