import Foundation

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
        self.maxBytes = width * height * pixelFormat.rawValue * sampleBits / 8
        self.rgbBackground = rgbBackground
    }
}

public protocol Slide {
    var id: UUID { get }
    var mainPath: String { get }
    var name: String { get }
    var format: String { get }
    var dataSize: Int { get }
    var scanObjective: Int { get }
    var scanScale: Double { get }
    var tileTrait: TileTrait { get }
    var layerZoom: Int { get }

    var layerImageSize: [(w: Int, h: Int)] { get }
    var layerTileSize: [(r: Int, c: Int)] { get }
    var tierCount: Int { get }
    
    @available(*, deprecated, message: "Use return Array version")
    func fetchLabelJPEGImage() -> Data
    @available(*, deprecated, message: "Use return Array version")
    func fetchMacroJPEGImage() -> Data
    @available(*, deprecated, message: "Use return Array version")
    func fetchTileRawImage(at coord: TileCoordinate) -> Data

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
}
