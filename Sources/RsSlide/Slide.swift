import Foundation
import LibJPEGTurbo
import MBL
import RsHelper

public struct TileCoordinate {
    let layer: Int
    let row: Int
    let col: Int
    let tier: Int
    let channel: Int
    
    public init(layer: Int, row: Int, col: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = 0
        self.channel = 0
    }
    public init(layer: Int, row: Int, col: Int, tier: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = tier
        self.channel = 0
    }
    public init(layer: Int, row: Int, col: Int, channel: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = 0
        self.channel = channel
    }
}

public struct TileTrait: CustomStringConvertible {
    public enum CompressionHint {
        case jpeg
        case png
        case jxl
    }
    public enum PixelFormatHint: Int {
        case rgb = 3
        case gray = 1
    }
    
    public let size: (w: Int, h: Int)
    public let compression: CompressionHint
    public let pixelFormat: PixelFormatHint
    public let sampleBits: Int
    public let pitchBytes: Int
    public let maxBytes: Int
    public let rgbBackground: Int
    
    public var description: String {
        switch (compression, pixelFormat, sampleBits) {
        case (.jpeg, .rgb, 8):
            return "JPEG_RGB_24bits"
        default:
            fatalError()
        }
    }
    
    init(width: Int, height: Int,
         compression: CompressionHint = .jpeg,
         pixelFormat: PixelFormatHint = .rgb,
         sampleBits: Int = 8,
         rgbBackground: Int = 0xFFFFFF) {
        self.size = (width, height)
        self.compression = compression
        self.pixelFormat = pixelFormat
        self.sampleBits = sampleBits
        self.pitchBytes = width * pixelFormat.rawValue * sampleBits / 8
        self.maxBytes = height * self.pitchBytes
        self.rgbBackground = rgbBackground
    }
}

public protocol Slide {
    var id: UUID { get }
    var mainPath: String { get }
    var createTime: Date { get }
    var modifyTime: Date { get }
    var name: String { get }
    var format: String { get }
    var dataSize: Int { get }
    var scanObjective: Int { get }
    var scanScale: Double { get }
    var tileTrait: TileTrait { get }
    var layerZoom: Int { get }
    var extendXMLString: String { get }

    var layerImageSize: [(w: Int, h: Int)] { get }
    var layerTileSize: [(r: Int, c: Int)] { get }
    var tierCount: Int { get }
    var tierSpacing: Double { get }

    func fetchLabelJPEGImage() -> [UInt8]
    func fetchMacroJPEGImage() -> [UInt8]
    func fetchTileRawImage(at coord: TileCoordinate) -> [UInt8]
}

extension Slide {
    func validate(coord: TileCoordinate) -> Bool {
        return 0..<tierCount ~= coord.tier
        && 0..<layerTileSize.count ~= coord.layer
        && 0..<layerTileSize[coord.layer].r ~= coord.row
        && 0..<layerTileSize[coord.layer].c ~= coord.col
    }

    func trimTile(for rawImage: [UInt8], at coord: TileCoordinate) -> [UInt8] {
        guard tileTrait.pixelFormat == .rgb && tileTrait.sampleBits == 8 && tileTrait.compression == .jpeg else { return rawImage }

        var trimWidth = 0
        var trimHeight = 0
        if coord.row == layerTileSize[coord.layer].r - 1 {
            trimHeight = (coord.row + 1) * tileTrait.size.h - layerImageSize[coord.layer].h
        }
        if coord.col == layerTileSize[coord.layer].c - 1 {
            trimWidth = (coord.col + 1) * tileTrait.size.w - layerImageSize[coord.layer].w
        }
        guard trimWidth > 0 || trimHeight > 0 else { return rawImage }

        var tile = [UInt8](repeating: 0, count: tileTrait.maxBytes)
        tile.withUnsafeMutableBytes { destBuf in
            let tj = tj3Init(Int32(TJINIT_DECOMPRESS.rawValue))
            defer { tj3Destroy(tj) }

             _ = rawImage.withUnsafeBytes { srcBuf in 
                tj3Decompress8(tj, srcBuf.baseAddress, srcBuf.count, destBuf.baseAddress, Int32(tileTrait.pitchBytes), TJPF_RGB.rawValue)
            }
        }

        return tjCompress(tile, TJPF_RGB, tileTrait.size.w - trimWidth, tileTrait.size.h - trimHeight, tileTrait.pitchBytes)
    }
}

public extension Slide {
    func fetchThumbnailJPEGImage(with maxSize: Int = 512) -> [UInt8] {
        guard tileTrait.pixelFormat == .rgb
            && tileTrait.sampleBits == 8
            && tileTrait.compression == .jpeg else {
            log.error("Failed to fetch thumbnail JPEG image. Only support RGB24 JPEG format slide file.")
            return []
        }

        var layer = layerImageSize.count - 1
        while (layer > 0 && layerImageSize[layer].w < maxSize && layerImageSize[layer].h < maxSize) {
            layer -= 1
        }
        guard layer >= 0 else { return [] }

        let layerWidth = layerImageSize[layer].w
        let layerHeight = layerImageSize[layer].h
        let layerPitch = layerWidth * 3
        var layerRGBImage = [UInt8](repeating: 0, count: layerPitch * layerHeight)

        let tj = tj3Init(Int32(TJINIT_DECOMPRESS.rawValue))
        defer { tj3Destroy(tj) }

        layerRGBImage.withUnsafeMutableBytes { buf in
            for row in 0..<layerTileSize[layer].r {
                for col in 0..<layerTileSize[layer].c {
                    let coord = TileCoordinate(layer: layer, row: row, col: col)
                    let img = fetchTileRawImage(at: coord)
                    _ = img.withUnsafeBytes { tile_buf in 
                        tj3Decompress8(tj, tile_buf.baseAddress, tile_buf.count,
                            buf.baseAddress! + row * tileTrait.size.h * layerPitch + col * tileTrait.size.w * 3, Int32(layerPitch), TJPF_RGB.rawValue)
                    }
                }
            }
        }

        var thumbnailWidth = maxSize
        var thumbnailHeight = maxSize
        if layerWidth > layerHeight {
            thumbnailHeight = thumbnailWidth * layerHeight / layerWidth
        } else if layerWidth < layerHeight {
            thumbnailWidth = thumbnailHeight * layerWidth / layerHeight
        }

        if (thumbnailWidth, thumbnailHeight) == (layerWidth, layerHeight) {
            return tjCompress(layerRGBImage, TJPF_RGB, layerWidth, layerHeight)
        } else {
            let thumbnail = scaleImage(layerRGBImage, layerWidth, layerHeight, thumbnailWidth, thumbnailHeight)
            return tjCompress(thumbnail, TJPF_RGB, thumbnailWidth, thumbnailHeight)
        }
    }
}
