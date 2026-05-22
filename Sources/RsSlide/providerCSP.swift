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
    var id: Foundation.UUID {
        get {
            let fingerprint = """
            """

            return Data(fingerprint.utf8).hashUUID
        }
    }
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
        return nil
    }()
    
    init?(path: URL) {
        return nil
    }

    deinit {
    }
    
    func fetchLabelJPEGImage() -> [UInt8]? {
        return nil
    }
    
    func fetchMacroJPEGImage() -> [UInt8]? {
        return nil
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
    
    init() {
        getCspReader = dll.getProc("GetCspReader")
        destroyCspReader = dll.getProc("DestroyCspReader")
        cspReadPreview = dll.getProc("CspReadPreview")
        cspReadLabel = dll.getProc("CspReadLabel")
        cspDestroyImage = dll.getProc("CspDestroyImage")
    }
}
