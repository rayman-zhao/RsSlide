import Foundation
import WinSDK
import RsHelper
import CVendorSDKs

fileprivate let dll = libcsp_sdk()

struct CSPPreview : SlidePreview {
    let path: URL

    func fetchMacroJPEGImage() -> [UInt8]? {
        guard let fp = dll.getCspReader?(path.filePath.oemCString) else { return nil }
        defer { dll.destroyCspReader?(fp) }

        var info = CspImageInfo()
        guard dll.cspReadPreview?(fp, &info) == 0 else { return nil }
        defer { dll.cspDestroyImage?(&info) }

        var pixels = [UInt8](repeating: 0, count: Int(info.dataLen))
        memcpy(&pixels, info.data, Int(info.dataLen))
        return pixels
    }
}

final class CSP : Slide {   
    let cspReader: UnsafeRawPointer
    var cspConfig = CspConfig()
    var cspScannerInfo = CspScannerInfo()

    lazy var id: Foundation.UUID = {
        let fingerprint = """
        dataSize: \(dataSize)
        cspConfig: \(cspConfig)
        cspScannerInfo: \(cspScannerInfo)
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
        guard let fp = dll.getCspReader?(path.filePath.oemCString) else { return nil }
        cspReader = fp

        mainPath = path.filePath
        let rv = try? path.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        createTime = rv?.creationDate ?? Date(timeIntervalSince1970: 0)
        modifyTime = rv?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        name = path.deletingPathExtension().lastPathComponent
        format = path.pathExtension.uppercased()
        dataSize = path.fileSize

        guard dll.cspReadScannerInfo?(cspReader, &cspScannerInfo) == 0 else { return nil }
        guard dll.cspReadConfig?(cspReader, &cspConfig) == 0 else { return nil }
        scanObjective = Int(cspConfig.scanRatio)
        scanScale = Double(cspConfig.mpp)
        tileTrait = TileTrait(width: Int(cspConfig.tileWidth), height: Int(cspConfig.tileHeight))
        layerZoom = Int(cspConfig.downsamplingRatio)

        var imageWidth = Float(cspConfig.imageWidth)
        var imageHeight = Float(cspConfig.imageHeight)
        var layerNum: UInt32 = 0
        guard dll.cspGetLayerNum?(cspReader, &layerNum) == 0 && layerNum > 0 else { return nil }
        for _ in 0..<layerNum {
            layerImageSize.append((Int(imageWidth), Int(imageHeight)))
            layerTileSize.append((
                Int(ceil(imageHeight / Float(cspConfig.tileHeight))),
                Int(ceil(imageWidth / Float(cspConfig.tileWidth)))
            ))

            imageWidth = ceil(imageWidth / cspConfig.downsamplingRatio)
            imageHeight = ceil(imageHeight / cspConfig.downsamplingRatio)
        }
    }

    deinit {
        dll.destroyCspReader?(cspReader)
    }
    
    func fetchLabelJPEGImage() -> [UInt8]? {
        var info = CspImageInfo()
        guard dll.cspReadLabel?(cspReader, &info) == 0 else { return nil }
        defer { dll.cspDestroyImage?(&info) }

        var pixels = [UInt8](repeating: 0, count: Int(info.dataLen))
        memcpy(&pixels, info.data, Int(info.dataLen))
        return pixels
    }
    
    func fetchMacroJPEGImage() -> [UInt8]? {
        var info = CspImageInfo()
        guard dll.cspReadPreview?(cspReader, &info) == 0 else { return nil }
        defer { dll.cspDestroyImage?(&info) }

        var pixels = [UInt8](repeating: 0, count: Int(info.dataLen))
        memcpy(&pixels, info.data, Int(info.dataLen))
        return pixels
    }

    func fetchTileRawImage(at coord: TileCoordinate) -> [UInt8]? {
        return nil
    }
}

fileprivate final class libcsp_sdk: @unchecked Sendable {
    private let dll = DllLoader("libcsp_sdk", "csp")

    let getCspReader: (@convention(c) (UnsafePointer<CChar>?) -> UnsafeRawPointer)?
    let destroyCspReader: (@convention(c) (UnsafeRawPointer) -> Void)?
    let cspReadPreview: (@convention(c) (UnsafeRawPointer, UnsafeMutablePointer<CspImageInfo>) -> Int32)?
    let cspReadLabel: (@convention(c) (UnsafeRawPointer, UnsafeMutablePointer<CspImageInfo>) -> Int32)?
    let cspDestroyImage: (@convention(c) (UnsafePointer<CspImageInfo>) -> Void)?
    let cspReadScannerInfo: (@convention(c) (UnsafeRawPointer, UnsafeMutablePointer<CspScannerInfo>) -> Int32)?
    let cspReadConfig: (@convention(c) (UnsafeRawPointer, UnsafeMutablePointer<CspConfig>) -> Int32)?
    let cspGetLayerNum: (@convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt32>) -> Int32)?
    
    init() {
        getCspReader = dll.getProc("GetCspReader")
        destroyCspReader = dll.getProc("DestroyCspReader")
        cspReadPreview = dll.getProc("CspReadPreview")
        cspReadLabel = dll.getProc("CspReadLabel")
        cspDestroyImage = dll.getProc("CspDestroyImage")
        cspReadScannerInfo = dll.getProc("CspReadScannerInfo")
        cspReadConfig = dll.getProc("CspReadConfig")
        cspGetLayerNum = dll.getProc("CspGetLayerNum")
    }
}
