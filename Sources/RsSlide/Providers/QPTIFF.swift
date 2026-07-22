import Foundation
import LibTIFF
import RsFoundation

struct QPTIFFPreview: SlidePreview {
    let path: URL

    func fetchMacroJPEGImage() -> [UInt8]? {
        #if os(Windows)
            let tiff = TIFFOpenW(path.path.wideString, "rh")
        #else
            let tiff = TIFFOpen(path.path, "rh")
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

final class QPTIFF: Slide {
    private let tiff: OpaquePointer
    private var layerDir: [UInt32] = []
    private var tilePhotometric = 0
    private var macroDir: UInt32 = 0
    private var labelDir: UInt32 = 0
    private var imageDesc = ""
    private var quality = 85
    private var gamma: Double? = nil

    lazy var id: UUID = {
        let fingerprint = """
            dataSize: \(dataSize)
            imageDesc: \(imageDesc)
            layers: \(layerImageSize)
            """

        return Data(fingerprint.utf8).hashUUID
    }()
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
        name = path.deletingPathExtension().lastPathComponent
        format = path.pathExtension.uppercased()
        dataSize = path.fileSize

        // importDirectories()

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
        guard macroDir != 0 else { return nil }
        return TIFFReadJPEGImage(tiff, macroDir)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        // let layer = coord.layer
        // guard layer < layerTileSize.count else { return nil }
        // let tileCount = layerTileSize[layer]
        // guard coord.row < tileCount.r && coord.col < tileCount.c else { return nil }

        // let dirIndex = UInt32(layer * tileCount.r * tileCount.c + coord.row * tileCount.c + coord.col)
        // guard TIFFSetDirectory(tiff, dirIndex) == 1 else { return nil }

        // let raw = TIFFReadRawImage(tiff)
        // return raw.isEmpty ? nil : raw
        return nil
    }
}
