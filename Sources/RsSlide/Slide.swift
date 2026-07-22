import Foundation
import LibJPEGTurbo

public struct TileCoordinate {
    let layer: Int
    let row: Int
    let col: Int
    let tier: Int
    let channel: Int

    public init(layer: Int, row: Int, col: Int, tier: Int = 0, channel: Int = 0) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = tier
        self.channel = channel
    }
}

public struct TileTrait: CustomStringConvertible {
    enum CompressionHint {
        case jpeg
        case png
        case jxl
    }
    enum PixelFormatHint: Int {
        case rgb = 3
        case gray = 1
    }

    let size: (w: Int, h: Int)
    let compression: CompressionHint
    let pixelFormat: PixelFormatHint
    let sampleBits: Int
    let backgroundColorRGB: Int

    var maxBytes: Int {
        return size.h * pitchBytes
    }

    var pixelBytes: Int {
        return pixelFormat.rawValue * sampleBits / 8
    }

    var pitchBytes: Int {
        return size.w * pixelBytes
    }

    var tjPF: TJPF {
        switch pixelFormat {
        case .rgb:
            return TJPF_RGB
        case .gray:
            return TJPF_GRAY
        }
    }

    public var description: String {
        switch (compression, pixelFormat, sampleBits) {
        case (.jpeg, .rgb, 8):
            return "JPEG_RGB_24bits"
        default:
            fatalError()
        }
    }

    init(
        width: Int, height: Int,
        compression: CompressionHint = .jpeg,
        pixelFormat: PixelFormatHint = .rgb,
        sampleBits: Int = 8,
        backgroundColorRGB: Int = 0xFFFFFF
    ) {
        self.size = (width, height)
        self.compression = compression
        self.pixelFormat = pixelFormat
        self.sampleBits = sampleBits
        self.backgroundColorRGB = backgroundColorRGB
    }
}

/// Pixel data of a slide layer, decompressed and packed row by row.
public struct LayerPixelData {
    let pixels: [UInt8]
    let layer: Int
    let width: Int
    let pitch: Int
    let height: Int
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
    var tierCount: Int { get }
    var tierSpacing: Double { get }
    var tileTrait: TileTrait { get }
    var layerZoom: Int { get }
    var extendedXML: String { get }

    var layerImageSize: [(w: Int, h: Int)] { get }
    var layerTileSize: [(r: Int, c: Int)] { get }

    /// Cached pixel data of the base (smallest) layer, generated once per provider.
    ///
    /// - Important: This is an implementation detail used internally by
    ///   `fetchVirtualTileImage`, `fetchThumbnailJPEGImage`, and `saveAsSVS`.
    ///   Do not access directly; treat it as if it were `internal`.
    var topLayerPixelData: LayerPixelData? { get }

    func fetchLabelJPEGImage() -> [UInt8]?
    func fetchMacroJPEGImage() -> [UInt8]?
    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]?
}
