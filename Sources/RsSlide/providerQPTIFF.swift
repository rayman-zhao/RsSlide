import Foundation
import LibTIFF
import RsFoundation

struct QPTIFFPreview : SlidePreview {
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
        
        return TIFFReadJPEGImage(tiff, TIFFNumberOfDirectories(tiff) - 1)
    }
}

final class QPTIFF : Slide {
    let tiff: OpaquePointer
    var layerDir: [UInt32] = []
    var tilePhotometric = 0
    var macroDir: UInt32 = 0
    var labelDir: UInt32 = 0
    var imageDesc = ""
    var quality = 85
    var gamma: Double? = nil
    
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
    let extendXMLString: String = ""
    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []

    lazy var baseLayerPixelData: (pixels: [UInt8], layer: Int, width: Int, pitch: Int, height: Int)? = {
        fetchPixelData(at: layerTileSize.count - 1)
    }()
    
    init?(path: URL) {
    #if os(Windows)
        guard let tiff = TIFFOpenW(path.path.wideString, "rh") else { return nil }
    #else
        guard let tiff = TIFFOpen(path.path, "rh") else { return nil } // h - Read TIFF header only, do not load the first directory.
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

    func fetchTileRawImage(at coord: TileCoordinate) -> [UInt8]? {
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
