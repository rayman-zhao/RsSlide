import Foundation
import FoundationXML
import LibJPEGTurbo
import LibTIFF
import RsFoundation

struct OMETIFFPreview: SlidePreview {
    let path: URL

    func fetchMacroJPEGImage() -> [UInt8]? {
        #if os(Windows)
            let tiff = TIFFOpenW(path.path.wideString, "r")
        #else
            let tiff = TIFFOpen(path.path, "r")
        #endif
        guard tiff != nil else { return nil }
        defer {
            TIFFClose(tiff)
        }

        let subifd: (count: UInt16?, offset: UnsafeMutablePointer<UInt64>?) = TIFFGetField(tiff, TIFFTAG_SUBIFD)
        if let count = subifd.count,
            let offset = subifd.offset, count > 0,
            let macro = TIFFReadJPEGImage(tiff, 0, offset.pointee)
        {  // Usually the macro image in mainifd is too big, so that use the first subifd instead.
            return macro
        }

        return TIFFReadJPEGImage(tiff, 0)
    }
}

final class OMETIFF: Slide {
    private enum LayerData {
        case tile(UInt32, UInt64?)
        case strip(UInt32, UInt64, [UInt32]?, UInt32, UInt32)
    }

    private let tiff: OpaquePointer
    private var layerData: [LayerData] = []
    private var tilePhotometric = 0
    private var labelDir: UInt32 = 0
    private let quality = 85

    var id: UUID = UUID()
    var mainPath: String
    var createTime: Date
    var modifyTime: Date
    var name: String
    var format: String
    var dataSize: Int = -1
    var scanObjective = 0
    var scanScale = 0.0
    let tierCount: Int = 1
    let tierSpacing: Double = 0.0
    var tileTrait: TileTrait = TileTrait(width: 0, height: 0)
    var layerZoom = 2
    let extendedXML: String = ""
    
    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []

    lazy var topLayerPixelData = fetchPixelData(at: layerTileSize.count - 1)

    init?(path: URL) {
        #if os(Windows)
            guard let tiff = TIFFOpenW(path.path.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(path.path, "rh") else { return nil }  // h - Read TIFF header only, do not load the first directory.
        #endif
        self.tiff = tiff

        mainPath = path.path
        let rv = try? path.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        createTime = rv?.creationDate ?? Date(timeIntervalSince1970: 0)
        modifyTime = rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        name = path.lastPathComponent
        if name.hasSuffix(".ome.tif") {
            name.removeLast(8)
            format = "OME.TIF"
        } else if name.hasSuffix(".ome.tiff") {
            name.removeLast(9)
            format = "OME.TIFF"
        } else {
            name = path.deletingPathExtension().lastPathComponent
            format = path.pathExtension.uppercased()
        }
        dataSize = path.fileSize

        importDirectories()

        if layerTileSize.count > 1 {
            // The 2312399.svs has 4.00036166 zoom, so that use tile size instead.
            //layerZoom = Int(ceil(Double(layerImageSize[0].w) / Double(layerImageSize[1].w)))
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
        return TIFFReadJPEGImage(tiff, 0)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }

        switch layerData[coord.layer] {
        case .tile(let dirnum, let diroffset):
            guard TIFFSetDirectory(tiff, dirnum, diroffset) else { return nil }

            let tileX = UInt32(coord.col * tileTrait.size.w)
            let tileY = UInt32(coord.row * tileTrait.size.h)
            let tid = TIFFComputeTile(tiff, tileX, tileY, 0, 0)
            let pixelCount = tileTrait.size.w * tileTrait.size.h
            if tilePhotometric == PHOTOMETRIC_RGB {
                var buf = [UInt32](repeating: 0, count: pixelCount)
                guard TIFFReadRGBATile(tiff, tileX, tileY, &buf) > 0 else { return nil }
                return tjCompress(buf, TJPF_RGBA, tileTrait.size.w, tileTrait.size.h, 0, quality, true)
            } else {
                let bufSize = pixelCount * tileTrait.pixelBytes
                var buf = [UInt8](repeating: 0, count: bufSize)
                let tileSize = Int(TIFFReadRawTile(tiff, tid, &buf, tmsize_t(bufSize)))
                return Array(buf[..<tileSize])
            }
        case .strip(let dirnum, let diroffset, var buf, let w, let h):
            if buf == nil {
                guard TIFFSetDirectory(tiff, dirnum, diroffset) else { return nil }
                let bufSize = Int(w * h)
                buf = [UInt32](repeating: 0, count: bufSize)
                guard TIFFReadRGBAImageOriented(tiff, w, h, &buf!, ORIENTATION_TOPLEFT, 0) == 1 else { return nil }
                layerData[coord.layer] = .strip(dirnum, diroffset, buf, w, h)
            }

            let iw = Int(w)
            let ih = Int(h)
            let tileX = coord.col * tileTrait.size.w
            let tileY = coord.row * tileTrait.size.h
            let tileWidth = min(tileTrait.size.w, iw - tileX)
            let tileHeight = min(tileTrait.size.h, ih - tileY)
            var tilePixels = [UInt32](repeating: 0, count: tileWidth * tileHeight)

            for row in 0..<tileHeight {
                let srcStart = (tileY + row) * iw + tileX
                let dstStart = row * tileWidth
                tilePixels[dstStart..<(dstStart + tileWidth)] = buf![srcStart..<(srcStart + tileWidth)]
            }

            return tjCompress(tilePixels, TJPF_RGBA, tileWidth, tileHeight, 0, quality)
        }
    }

    private func importDirectories() {
        while TIFFReadDirectory(tiff) == 1 {
            let dir = TIFFCurrentDirectory(tiff)
            let tw: UInt32? = TIFFGetField(tiff, TIFFTAG_TILEWIDTH)

            if dir == 0 {  // First directory always be macro image.
                importMetadata()
            } else if tw != nil {  // Pyramid layer image.
                importLayers(from: dir)
            } else if labelDir == 0 {
                labelDir = dir
            }
        }
    }

    private func importMetadata() {
        if let desc: UnsafeMutablePointer<CChar> = TIFFGetField(tiff, TIFFTAG_IMAGEDESCRIPTION),  // libtiff keep this const char * memory
            let xml = try? XMLDocument(xmlString: String(cString: desc))
        {
            xml.forEachElement { parent, name, attribute, value in
                if parent == "OME" && name == "OME" && attribute == "UUID",
                    let v = UUID(uuidString: String(value.dropFirst("urn:uuid:".count)))
                {
                    id = v
                } else if parent == "Instrument" && name == "Objective" && attribute == "NominalMagnification",
                    let v = Double(value), v > 0
                {
                    scanObjective = Int(v)
                } else if parent == "Image" && name == "Pixels" && attribute == "PhysicalSizeX",
                    let v = Double(value), v > 0.0 && (scanScale == 0.0 || v < scanScale)
                {
                    scanScale = v
                } else if parent == "Image" && name == "Pixels" && attribute == "PhysicalSizeXUnit" && value == "mm" {
                    scanScale *= 1000.0
                } else {
                    log.trace("Ignore \(parent) - \(name) - \(attribute) - \(value)")
                }
            }
        }
    }

    private func importLayers(from dir: UInt32) {
        if let tw: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH),
            let th: UInt32 = TIFFGetField(tiff, TIFFTAG_TILELENGTH)
        {
            tileTrait = TileTrait(width: Int(tw), height: Int(th))
        }
        if let photometric: UInt16 = TIFFGetField(tiff, TIFFTAG_PHOTOMETRIC) {
            tilePhotometric = Int(photometric)
        }

        layerData.append(.tile(dir, nil))  // The main directory offset is always nil.
        if let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
            let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
        {
            layerImageSize.append((Int(w), Int(h)))
            layerTileSize.append(
                (
                    Int(ceil(Double(h) / Double(tileTrait.size.h))),
                    Int(ceil(Double(w) / Double(tileTrait.size.w)))
                ))
        }

        let subifd: (count: UInt16?, ptr: UnsafeMutablePointer<UInt64>?) = TIFFGetField(tiff, TIFFTAG_SUBIFD)
        if let count = subifd.count, let ptr = subifd.ptr {
            let offset = Array(UnsafeBufferPointer(start: ptr, count: Int(count)))  // Need to copy, otherwise the pointer will be invalid after TIFFSetSubDirectory.
            for diroffset in offset {
                guard TIFFSetSubDirectory(tiff, diroffset) == 1 else { break }
                guard let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
                    let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
                else { break }

                if let _: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH) {
                    layerData.append(.tile(dir, diroffset))
                } else {  // The Lecia-1 has strip image in reduced-resolution layer
                    layerData.append(.strip(dir, diroffset, nil, w, h))
                }

                layerImageSize.append((Int(w), Int(h)))
                layerTileSize.append(
                    (
                        Int(ceil(Double(h) / Double(tileTrait.size.h))),
                        Int(ceil(Double(w) / Double(tileTrait.size.w)))
                    ))
            }

            TIFFSetDirectory(tiff, dir)
        }
    }
}
